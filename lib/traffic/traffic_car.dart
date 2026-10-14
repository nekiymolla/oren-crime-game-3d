import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import '../world/road_graph.dart';
import 'traffic_signals.dart';

/// Типы `highway`, по которым ездит фоновый трафик. Как vehicleHighwayTypes
/// у полиции, но БЕЗ `service`: это проезды к подъездам и парковки, и
/// именно на них правая полоса задевает дома (2 ребра из 1074 при сдвиге
/// 1.5 м, см. tools/osm_pipeline/check_road_graph.mjs). Сквозной поток во
/// дворы и не заезжает — полиции туда можно, трафику незачем.
const Set<String> trafficHighwayTypes = {
  'residential',
  'unclassified',
  'tertiary',
  'secondary',
  'primary',
  'living_street',
};

/// Полуширина нарисованного асфальта по типу дороги, метры. Замерено по
/// материалам чанков (14.10.2026): у `residential` асфальт кончается на
/// ~2.0 м от оси (дорога 4 м, как настоящие дворовые проезды), у
/// `tertiary`/`unclassified` — на ~3.5 м. osm2world берёт ширину из
/// тегов/умолчаний, так что это свойство данных, а не догадка.
double roadHalfWidthFor(String highway) => switch (highway) {
  'residential' || 'living_street' => 2.0,
  _ => 3.5,
};

/// Сдвиг центра машины от оси дороги вправо, метры: правостороннее
/// движение. Полоса — середина своей половины асфальта, но не ближе
/// полуширины кузова к краю. Раньше был один сдвиг 1.5 м на все дороги — и
/// на узких дворовых машина свешивалась на тротуар на 0.4 м (замечено
/// вживую). На 4-метровой дворовой встречные расходятся впритирку, как и в
/// жизни.
double laneOffsetFor(String highway) => switch (highway) {
  'residential' || 'living_street' => 1.2,
  _ => 1.75,
};

/// Дальше этого от узла точку поворота не выносим (см. cornerPoint).
const double _maxCornerOffset = 3.5;

/// Дорожная сеть для трафика — чистые данные и геометрия полос, без
/// flutter_scene (проверяется юнит-тестами без GPU).
class TrafficNetwork {
  TrafficNetwork(this.graph) {
    for (final edge in graph.edges) {
      if (!trafficHighwayTypes.contains(edge.highway)) continue;
      _addDirected(edge.from, edge.to, edge);
      if (!edge.oneway) _addDirected(edge.to, edge.from, edge);
    }
  }

  final RoadGraph graph;

  /// Куда можно уехать из узла (с учётом oneway).
  final Map<String, List<String>> adjacency = {};
  final Map<String, RoadGraphEdge> _edges = {};

  final Map<String, Set<String>> _undirected = {};

  void _addDirected(String from, String to, RoadGraphEdge edge) {
    (adjacency[from] ??= []).add(to);
    _edges['$from|$to'] = edge;
    (_undirected[from] ??= {}).add(to);
    (_undirected[to] ??= {}).add(from);
  }

  /// Настоящий перекрёсток (3+ направления), а не изгиб дороги — на нём
  /// машины проезжают по одной (см. TrafficDriving.junctionClaimRadius).
  bool isJunction(String nodeId) => (_undirected[nodeId]?.length ?? 0) >= 3;

  RoadGraphEdge? edge(String from, String to) => _edges['$from|$to'];

  /// Сдвиг полосы вправо от оси для ребра from -> to; на односторонних —
  /// по оси (там обе полосы в одну сторону).
  double laneOffset(String from, String to) {
    final e = edge(from, to);
    if (e == null || e.oneway) return 0.0;
    return laneOffsetFor(e.highway);
  }

  /// Начало полосы ребра from -> to — куда ставить машину при спавне.
  vm.Vector3 laneStart(String from, String to) {
    final a = graph.nodes[from]!;
    final start = a.toVector3();
    final direction = _direction(a, graph.nodes[to]!);
    if (direction == null) return start;
    return start + rightOf(direction) * laneOffset(from, to);
  }

  /// Крейсерская скорость по типу дороги, м/с — во дворах ползут, на
  /// магистралях едут бодрее (числа на глаз, ~20-60 км/ч).
  double cruiseSpeed(String from, String to) => switch (edge(from, to)?.highway) {
    'primary' => 16.0,
    'secondary' => 14.0,
    'tertiary' => 12.0,
    'living_street' => 5.0,
    _ => 9.0,
  };

  /// Точка полосы, к которой машина едет по ребру from -> to: конец ребра,
  /// сдвинутый вправо от направления движения. На односторонних — по оси
  /// (там обе полосы в одну сторону).
  vm.Vector3 lanePoint(String from, String to) {
    final a = graph.nodes[from]!;
    final b = graph.nodes[to]!;
    final target = b.toVector3();
    final direction = _direction(a, b);
    if (direction == null) return target;
    return target + rightOf(direction) * laneOffset(from, to);
  }

  /// Точка поворота при проезде from -> via -> to: пересечение линии
  /// полосы входящего ребра с линией полосы выходящего. Именно туда
  /// вписывается дуга поворота; при повороте через встречную (налево) она
  /// за узлом, направо — перед ним. Почти прямо или почти разворот (линии
  /// почти параллельны) — просто конец полосы входящего ребра.
  vm.Vector3 cornerPoint(String from, String via, String to) {
    final fallback = lanePoint(from, via);
    final a = graph.nodes[from];
    final b = graph.nodes[via];
    final c = graph.nodes[to];
    if (a == null || b == null || c == null) return fallback;
    final d1 = _direction(a, b);
    final d2 = _direction(b, c);
    if (d1 == null || d2 == null) return fallback;
    final cross = d1.x * d2.z - d1.z * d2.x;
    if (cross.abs() < 0.17) return fallback; // меньше ~10° или больше ~170°

    final p1 = lanePoint(from, via);
    final p2 = b.toVector3() + rightOf(d2) * laneOffset(via, to);
    // p1 + d1 * t = p2 + d2 * u  ->  t из 2D-векторного произведения.
    final w = p2 - p1;
    final t = (w.x * d2.z - w.z * d2.x) / cross;
    final corner = p1 + d1 * t;
    // На острых углах пересечение полос уходит далеко от перекрёстка —
    // машина резала бы угол по газону. Тогда поворот вписывается от конца
    // полосы, как раньше.
    if ((corner - b.toVector3()).length > _maxCornerOffset) return fallback;
    return corner;
  }

  /// Следующий узел после ребра from -> to: случайный выезд, кроме
  /// разворота назад; в тупике — разворот. null — ехать некуда вообще.
  String? pickNext(String from, String to, math.Random random) {
    final exits = adjacency[to];
    if (exits == null || exits.isEmpty) return null;
    final forward = exits.where((id) => id != from).toList();
    final pool = forward.isNotEmpty ? forward : exits;
    return pool[random.nextInt(pool.length)];
  }

  /// Угол поворота (0..pi) на узле [via] при проезде from -> via -> to.
  double turnAngle(String from, String via, String to) {
    final a = graph.nodes[from];
    final b = graph.nodes[via];
    final c = graph.nodes[to];
    if (a == null || b == null || c == null) return 0.0;
    final d1 = _direction(a, b);
    final d2 = _direction(b, c);
    if (d1 == null || d2 == null) return 0.0;
    return math.acos(d1.dot(d2).clamp(-1.0, 1.0));
  }

  static vm.Vector3? _direction(RoadGraphNode a, RoadGraphNode b) {
    final d = vm.Vector3(b.x - a.x, 0, b.z - a.z);
    final length = d.length;
    if (length < 1e-6) return null;
    return d / length;
  }
}

/// Направление "вправо" от курса в координатах игры (x — восток, z — юг,
/// Y вверх, правая система): смотря на +Z, правая рука указывает на -X.
vm.Vector3 rightOf(vm.Vector3 forward) => vm.Vector3(-forward.z, 0, forward.x);

/// Препятствие, перед которым трафик тормозит: игрок, его машина,
/// полиция, пешеходы, другие машины трафика. [radius] — полуширина.
typedef TrafficObstacle = ({vm.Vector3 position, double radius});

/// Одна машина фонового трафика. Кинематическая — едет по рёбрам графа,
/// а не через VehicleControllerComponent с его физикой и тремя лучами по
/// всей сцене на кадр: для фонового потока это была бы ровно та цена, от
/// которой уходили (PROGRESS.md, оптимизация). Сквозь дома не проедет,
/// потому что рёбра графа с полосой их не задевают (проверка пайплайна).
class TrafficCar {
  TrafficCar({
    required this.position,
    required this.heading,
    required this.fromNodeId,
    required this.toNodeId,
    this.nextNodeId,
    this.priority = 0,
  });

  /// Кто кого пропускает при сближении сбоку (перекрёсток, слияние):
  /// уступает машина с меньшим приоритетом. Без явного правила две машины
  /// либо въезжали друг в друга, либо уступали друг другу вечно.
  final int priority;

  vm.Vector3 position;

  /// Курс, та же конвенция, что у VehicleControllerComponent.heading
  /// (0 = +Z, atan2(x, z)).
  double heading;
  double speed = 0.0;

  /// Текущее ребро, по которому едет машина, и выбранный заранее выезд с
  /// его конца — заранее, чтобы притормозить перед поворотом.
  String fromNodeId;
  String toNodeId;
  String? nextNodeId;

  /// Сколько секунд машина стоит на месте — система переселяет
  /// застрявших (тупик без выезда, вечная пробка).
  double stoppedSeconds = 0.0;

  /// Идёт разворот (см. TrafficDriving.uTurnHeadingError) — держится до
  /// выравнивания, а не до первого кадра, где ошибка курса чуть меньше
  /// порога: иначе на полпути машина переходила на широкий радиус и её
  /// выносило с дороги.
  bool isTurningAround = false;

  /// Сколько секунд машина на текущем ребре — кто из выезжающих с
  /// перекрёстка въехал на него раньше (см. правило перекрёстка в
  /// stepTrafficCar).
  double edgeSeconds = 0.0;

  /// Сколько секунд машина стоит НЕ на красный — то есть уступает кому-то
  /// по правилам вежливости. Дольше [TrafficDriving.patienceSeconds] —
  /// перестаёт уступать (см. stepTrafficCar): правила перекрёстка и
  /// приоритета иногда замыкаются в круг, и без этого машины ждали друг
  /// друга вечно.
  double impatientSeconds = 0.0;

  bool get isImpatient => impatientSeconds > TrafficDriving.patienceSeconds;

  vm.Vector3 get forward => vm.Vector3(math.sin(heading), 0, math.cos(heading));
}

/// Параметры вождения трафика. Константы, а не поля машины — все машины
/// потока водят одинаково, разные только скорости по типам дорог.
abstract final class TrafficDriving {
  static const double acceleration = 3.0;
  static const double braking = 7.0;

  /// Замедление, с которым планируется подъезд к повороту/препятствию —
  /// мягче максимального торможения, чтобы не клевать носом.
  static const double comfortDecel = 4.0;

  /// Минимальный радиус поворота, м, и предел скорости рысканья, рад/с.
  static const double minTurnRadius = 4.5;
  static const double slowTurnRadius = 2.2;
  static const double maxYawRate = 1.6;

  /// Скорость прохождения разворота на 180° — ниже её в повороты не
  /// сбрасывают.
  static const double tightTurnSpeed = 2.5;

  /// Скорость поворота больше 45° на узкую дорогу.
  static const double narrowTurnSpeed = 3.5;

  /// Разворот (курс мимо цели больше чем на [uTurnHeadingError] рад —
  /// тупик или обратный выезд с перекрёстка): ползком и по радиусу ровно
  /// в полосу — из своей во встречную, то есть радиус = сдвиг полосы (см.
  /// stepTrafficCar), но не меньше [uTurnMinRadius]. С обычным радиусом
  /// машину выносило на 7.5 м с дороги (симуляция по графу района).
  static const double uTurnHeadingError = 1.5;
  static const double uTurnDoneHeadingError = 0.3;
  static const double uTurnSpeed = 1.5;
  static const double uTurnMinRadius = 1.0;

  /// За сколько метров до конца полосы переключаться на следующее ребро,
  /// когда дуга не вписывается (разворот, тупик); обычные повороты
  /// начинаются за R * tan(угол / 2), см. _switchDistance.
  static const double reachRadius = 3.5;

  /// Конус, в котором видны препятствия: до [lookAhead] метров вперёд.
  static const double lookAhead = 22.0;

  /// Полуширина кузова и зазор, с которым машина объезжает (точнее, не
  /// объезжает, а тормозит перед) препятствием сбоку.
  static const double halfWidth = 0.9;
  static const double lateralMargin = 0.3;

  /// Встречные расходятся, если между бортами хотя бы столько; на дворовой
  /// полосы в 2.4 м — зазор 0.6. Ноль, а не запас: выезжающая с поворота
  /// машина ещё не выровнялась, и с запасом видела встречную очередь "в
  /// своей полосе" — вставала, а очередь ждала её (хоровод на перекрёстке,
  /// симуляция района). Реальные пересечения кузовов ловит тест.
  static const double oncomingMargin = 0.0;

  /// Нос машины от центра плюс дистанция, на которой она останавливается.
  static const double stopGap = 4.0;

  /// Ближняя зона для других машин трафика: впереди до [nearFieldAhead] м
  /// и шире конуса — до [nearFieldLateral] м вбок. Узкий конус замечал
  /// въезжающую сбоку машину, когда та уже была в кузове (симуляция по
  /// графу района: центры сходились на 1.1 м). Встречная полоса — в 3 м,
  /// поэтому зона чуть уже.
  static const double nearFieldAhead = 8.0;
  static const double nearFieldLateral = 2.7;

  /// Вплотную ближе этого — правило "кто сзади, тот уступает".
  static const double bubble = 6.0;

  /// Перекрёсток (узел с 3+ направлениями) занимает одна машина: та, что
  /// ближе этого к узлу и выезжает с него (раньше всех въехавшая), а если
  /// таких нет — ближайшая из подъезжающих. Остальные ждут на этом
  /// расстоянии от узла. Без правила при слиянии (две машины сворачивают
  /// на одно ребро с разных сторон) кузова въезжали друг в друга и так и
  /// застревали — симуляция района, 7170 кадров наложения.
  static const double junctionClaimRadius = 12.0;

  /// Сколько машина готова уступать, стоя не на красный, прежде чем
  /// поехать сама (см. TrafficCar.impatientSeconds). Физическую помеху
  /// прямо впереди нетерпеливая всё равно не таранит.
  static const double patienceSeconds = 5.0;

  /// Прижимание вправо перед встречной: замечаем её за столько метров,
  /// хотим между центрами столько, сдвигаемся не больше чем на столько.
  static const double squeezeLookAhead = 22.0;
  static const double squeezeWantedGap = 2.4;
  static const double maxSqueeze = 0.8;

  /// Встречная в колее: встать в стольких метрах (между центрами), а
  /// нетерпеливой — ползти со скоростью [creepSpeed], пока центры дальше
  /// [creepMinGap].
  static const double oncomingStopGap = 6.0;
  static const double creepSpeed = 1.0;
  static const double creepMinGap = 3.0;
}

/// Один шаг машины трафика. Возвращает false, если ехать дальше некуда
/// (ни одного выезда из узла) — пусть система переселит машину.
bool stepTrafficCar(
  TrafficCar car,
  TrafficNetwork network, {
  required double dt,
  required math.Random random,
  Iterable<TrafficObstacle> obstacles = const [],
  Iterable<TrafficCar> traffic = const [],
  TrafficSignals? signals,
}) {
  if (dt <= 0.0) return true;

  car.nextNodeId ??= network.pickNext(car.fromNodeId, car.toNodeId, random);

  // 1. Пора поворачивать на следующее ребро: до точки поворота осталось
  // меньше, чем нужно дуге минимального радиуса, чтобы вписаться из своей
  // полосы в новую (R * tan(угол / 2)). Раньше переключались на самом
  // узле — и на левом повороте машину выносило через ось во встречную
  // полосу, где она вставала лбом в лоб со встречной (симуляция по
  // графу района, пробка на 228 с).
  var target = _edgeTarget(network, car);
  final edgeDirection = _edgeDirection(network, car.fromNodeId, car.toNodeId);
  final ahead = edgeDirection == null ? 0.0 : (target - car.position).dot(edgeDirection);
  // Перед красным на ребро поворота не переключаемся: на острых поворотах
  // вписывание начинается раньше стоп-линии, и машина проскочила бы её.
  final waitsAtSignal = _signalStopDistance(car, network, signals) != null;
  if (ahead <= _switchDistance(network, car) && !waitsAtSignal) {
    final next = car.nextNodeId;
    if (next == null) {
      car.speed = 0.0;
      return false;
    }
    car.fromNodeId = car.toNodeId;
    car.toNodeId = next;
    car.nextNodeId = network.pickNext(car.fromNodeId, car.toNodeId, random);
    car.edgeSeconds = 0.0;
    target = _edgeTarget(network, car);
  }
  car.edgeSeconds += dt;

  // 2. Желаемая скорость: крейсерская по типу дороги, но с запасом на то,
  // чтобы успеть сбросить до скорости поворота на конце ребра.
  final cruise = network.cruiseSpeed(car.fromNodeId, car.toNodeId);
  var desired = cruise;
  final next = car.nextNodeId;
  final distanceToNode = (target - car.position).length;
  if (next != null) {
    final angle = network.turnAngle(car.fromNodeId, car.toNodeId, next);
    var cornerSpeed = math.max(
      TrafficDriving.tightTurnSpeed,
      cruise * math.pow(math.cos(angle / 2), 2),
    );
    // На узкой дороге (дворовая, 4 м) поворот — ползком: на 6 м/с машина
    // выходила из левого поворота, не успев выровняться в полосу, и
    // задевала ждущую встречную (симуляция района).
    final outgoing = network.edge(car.toNodeId, next);
    if (angle > math.pi / 4 && outgoing != null && roadHalfWidthFor(outgoing.highway) < 3.0) {
      cornerSpeed = math.min(cornerSpeed, TrafficDriving.narrowTurnSpeed);
    }
    desired = math.min(
      desired,
      math.sqrt(cornerSpeed * cornerSpeed + 2 * TrafficDriving.comfortDecel * distanceToNode),
    );
  } else {
    // Тупик без выезда — подъезжаем и встаём.
    desired = math.min(desired, math.sqrt(2 * TrafficDriving.comfortDecel * distanceToNode));
  }

  // 2б. Светофор на конце ребра — встаём у стоп-линии.
  final stopDistance = _signalStopDistance(car, network, signals);
  if (stopDistance != null) {
    desired = math.min(desired, math.sqrt(2 * TrafficDriving.comfortDecel * stopDistance));
  }

  // 3. Курс — на точку линии полосы в нескольких метрах впереди проекции
  // машины (pure pursuit), а не на конец ребра: целясь в конец, машина
  // после поворота сходилась бы к полосе только по мере приближения к нему.
  // Сильно мимо — сначала сбросить скорость, иначе на минимальном радиусе
  // машина кружила бы вокруг цели.
  final aim = _aimPoint(network, car, target);
  // Встречная близко и в узком зазоре (изгиб дворовой дороги, выезд с
  // поворота) — прижимаемся вправо, как живой водитель, а не встаём лоб в
  // лоб (симуляция района: встречные замирали в 1.3 м друг напротив друга).
  final squeeze = _oncomingSqueeze(car, traffic);
  if (squeeze > 0.0) aim.add(rightOf(car.forward) * squeeze);
  final toLane = aim - car.position;
  final desiredHeading = math.atan2(toLane.x, toLane.z);
  final headingError = _wrapAngle(desiredHeading - car.heading);
  if (headingError.abs() > TrafficDriving.uTurnHeadingError) {
    car.isTurningAround = true;
  } else if (headingError.abs() < TrafficDriving.uTurnDoneHeadingError) {
    car.isTurningAround = false;
  }
  final isUTurn = car.isTurningAround;
  if (isUTurn) {
    desired = math.min(desired, TrafficDriving.uTurnSpeed);
  } else if (headingError.abs() > 0.6) {
    desired = math.min(desired, TrafficDriving.tightTurnSpeed);
  }

  // 4. Препятствия впереди — тормозим так, чтобы встать за stopGap.
  final forward = car.forward;
  final right = rightOf(forward);
  for (final obstacle in obstacles) {
    final relative = obstacle.position - car.position;
    final along = relative.dot(forward);
    if (along <= 0.0 || along > TrafficDriving.lookAhead) continue;
    final lateral = relative.dot(right).abs();
    if (lateral > TrafficDriving.halfWidth + obstacle.radius + TrafficDriving.lateralMargin) continue;
    final gap = along - obstacle.radius - TrafficDriving.stopGap;
    desired = math.min(desired, gap <= 0.0 ? 0.0 : math.sqrt(2 * TrafficDriving.comfortDecel * gap));
  }

  // 4б. Другие машины трафика: в конусе — встать в очередь (как любое
  // препятствие), в ближней зоне сбоку — уступить, если у неё приоритет.
  const halfWidth = TrafficDriving.halfWidth;
  for (final other in traffic) {
    if (identical(other, car)) continue;
    final relative = other.position - car.position;
    final along = relative.dot(forward);
    if (along <= 0.0 || along > TrafficDriving.lookAhead) continue;
    final lateral = relative.dot(right).abs();
    // Встречная (курс почти против нашего) — помеха, только если кузова
    // реально пересекутся: на 4-метровой дворовой полосы в 2 м друг от
    // друга, и с обычным запасом встречные вставали бы лоб в лоб навечно.
    // Пропуск по приоритету и "кто сзади" к встречным тоже не относятся —
    // они просто разъезжаются.
    final isOncoming = forward.dot(other.forward) < -0.7;
    if (isOncoming && lateral >= halfWidth * 2 + TrafficDriving.oncomingMargin) continue;
    final inLane = lateral <= halfWidth * 2 + (isOncoming ? TrafficDriving.oncomingMargin : TrafficDriving.lateralMargin);
    final yieldsSideways = !car.isImpatient &&
        !isOncoming &&
        along <= TrafficDriving.nearFieldAhead &&
        lateral <= TrafficDriving.nearFieldLateral &&
        other.priority > car.priority;
    // Вплотную (слияние на перекрёстке: две машины свернули на одно ребро
    // с разных сторон) — уступает та, что сзади: сосед впереди меня больше,
    // чем я впереди него. При ничьей — приоритет. Правило несимметричное,
    // так что вечного взаимного уступания нет (симуляция: без него центры
    // сходились на 0.7 м).
    var yieldsBehind = false;
    if (!car.isImpatient && !isOncoming && relative.length2 < TrafficDriving.bubble * TrafficDriving.bubble) {
      final theirAlong = -relative.dot(other.forward);
      yieldsBehind = along > theirAlong + 0.3 ||
          ((along - theirAlong).abs() <= 0.3 && other.priority > car.priority);
    }
    if (!inLane && !yieldsSideways && !yieldsBehind) continue;
    if (isOncoming) {
      // Встречная в нашей колее: тормозим только у самого кузова — пока
      // едем, прижимаемся вправо (см. _oncomingSqueeze), а стоя рулить
      // нельзя. Нетерпеливая ползёт и подруливает, пока есть место.
      final oncomingGap = along - TrafficDriving.oncomingStopGap;
      var limit = oncomingGap <= 0.0 ? 0.0 : math.sqrt(2 * TrafficDriving.comfortDecel * oncomingGap);
      if (car.isImpatient && along > TrafficDriving.creepMinGap) limit = math.max(limit, TrafficDriving.creepSpeed);
      desired = math.min(desired, limit);
      continue;
    }
    final gap = along - halfWidth - TrafficDriving.stopGap;
    desired = math.min(desired, gap <= 0.0 ? 0.0 : math.sqrt(2 * TrafficDriving.comfortDecel * gap));
  }

  // 4в. Перекрёсток — по одной машине (см. junctionClaimRadius).
  final junctionHold = car.isImpatient ? null : _junctionHoldDistance(car, network, traffic);
  if (junctionHold != null) {
    desired = math.min(desired, math.sqrt(2 * TrafficDriving.comfortDecel * junctionHold));
  }

  // 5. Скорость к желаемой.
  if (car.speed < desired) {
    car.speed = math.min(desired, car.speed + TrafficDriving.acceleration * dt);
  } else {
    car.speed = math.max(desired, car.speed - TrafficDriving.braking * dt);
  }

  // 6. Поворот руля: не быстрее, чем позволяет радиус разворота.
  // На малой скорости руль выкручивается сильнее: радиус падает до
  // slowTurnRadius. С постоянными 4.5 м точка прицеливания (в 6 м) могла
  // оказаться внутри круга разворота, и машины кружили вокруг неё на месте
  // (симуляция района: две машины наматывали круги 45 с).
  final turnRadius = isUTurn
      ? math.max(TrafficDriving.uTurnMinRadius, network.laneOffset(car.fromNodeId, car.toNodeId))
      : car.speed.clamp(TrafficDriving.slowTurnRadius, TrafficDriving.minTurnRadius);
  final yawRate = math.min(TrafficDriving.maxYawRate, car.speed / turnRadius);
  final maxTurn = yawRate * dt;
  car.heading += headingError.clamp(-maxTurn, maxTurn);

  // 7. Едем.
  car.position += car.forward * (car.speed * dt);
  car.stoppedSeconds = car.speed < 0.3 ? car.stoppedSeconds + dt : 0.0;
  // Нетерпение копится, только пока стоим не на красный; поехали — сброс.
  if (car.speed >= 1.0) {
    car.impatientSeconds = 0.0;
  } else if (car.speed < 0.3 && stopDistance == null) {
    car.impatientSeconds += dt;
  }
  return true;
}

/// Сколько осталось до стоп-линии, если перед ней надо встать (красный;
/// жёлтый — только если успеваем мягко, иначе проезжаем, как живой
/// водитель), или null — ехать.
double? _signalStopDistance(TrafficCar car, TrafficNetwork network, TrafficSignals? signals) {
  if (signals == null) return null;
  final light = signals.lightForEdge(car.fromNodeId, car.toNodeId);
  if (light == null || light == SignalLight.green) return null;
  final node = network.graph.nodes[car.toNodeId];
  final direction = _edgeDirection(network, car.fromNodeId, car.toNodeId);
  if (node == null || direction == null) return null;
  final stop = (node.toVector3() - car.position).dot(direction) - signalStopLineBack;
  if (stop < -0.5) return null; // уже за линией — освобождаем перекрёсток
  if (light == SignalLight.yellow && stop < car.speed * car.speed / (2 * TrafficDriving.comfortDecel)) {
    return null;
  }
  return math.max(0.0, stop);
}

/// Если перекрёсток впереди (или тот, с которого машина выезжает) занят
/// другой машиной — сколько ещё можно проехать до рубежа ожидания (0 —
/// стоять). null — путь свободен.
double? _junctionHoldDistance(TrafficCar car, TrafficNetwork network, Iterable<TrafficCar> traffic) {
  const radius = TrafficDriving.junctionClaimRadius;
  for (final (junctionId, leaving) in [(car.fromNodeId, true), (car.toNodeId, false)]) {
    if (!network.isJunction(junctionId)) continue;
    final junction = network.graph.nodes[junctionId]!.toVector3();
    final myDistance = (junction - car.position).length;
    if (leaving && myDistance > radius) continue;
    if (!leaving && myDistance > radius + 15.0) continue;

    for (final other in traffic) {
      if (identical(other, car)) continue;
      final otherLeaving = other.fromNodeId == junctionId;
      if (!otherLeaving && other.toNodeId != junctionId) continue;
      final otherDistance = (junction - other.position).length;
      if (otherDistance > radius) continue;

      final bool otherOwns;
      if (leaving) {
        // Я уже на выезде: уступаю только выезжающему, въехавшему раньше.
        otherOwns = otherLeaving &&
            (other.edgeSeconds > car.edgeSeconds + 1e-6 ||
                ((other.edgeSeconds - car.edgeSeconds).abs() <= 1e-6 && other.priority > car.priority));
      } else {
        otherOwns = otherLeaving ||
            otherDistance < myDistance - 0.5 ||
            ((otherDistance - myDistance).abs() <= 0.5 && other.priority > car.priority);
      }
      // Попутная в моей же полосе впереди — это очередь, её держит конус.
      if (otherOwns && !_sameLaneAhead(car, other)) {
        return leaving ? 0.0 : math.max(0.0, myDistance - radius);
      }
    }
  }
  return null;
}

/// Едет ли [other] впереди [car] в ту же сторону по тому же ребру —
/// тогда это очередь, а не конфликт на перекрёстке.
bool _sameLaneAhead(TrafficCar car, TrafficCar other) =>
    other.fromNodeId == car.fromNodeId &&
    other.toNodeId == car.toNodeId &&
    (other.position - car.position).dot(car.forward) > 0.0;

/// На сколько метров прижаться вправо из-за встречных впереди.
double _oncomingSqueeze(TrafficCar car, Iterable<TrafficCar> traffic) {
  final forward = car.forward;
  final right = rightOf(forward);
  var squeeze = 0.0;
  for (final other in traffic) {
    if (identical(other, car) || forward.dot(other.forward) >= -0.7) continue;
    final relative = other.position - car.position;
    final along = relative.dot(forward);
    if (along <= 0.0 || along > TrafficDriving.squeezeLookAhead) continue;
    final lateral = relative.dot(right).abs();
    squeeze = math.max(squeeze, ((TrafficDriving.squeezeWantedGap - lateral) / 2).clamp(0.0, TrafficDriving.maxSqueeze));
  }
  return squeeze;
}

/// Куда ведёт текущее ребро: точка поворота на следующее, если оно уже
/// выбрано, иначе конец полосы.
vm.Vector3 _edgeTarget(TrafficNetwork network, TrafficCar car) {
  final next = car.nextNodeId;
  return next == null
      ? network.lanePoint(car.fromNodeId, car.toNodeId)
      : network.cornerPoint(car.fromNodeId, car.toNodeId, next);
}

/// За сколько метров до точки поворота начинать поворот.
double _switchDistance(TrafficNetwork network, TrafficCar car) {
  final next = car.nextNodeId;
  if (next == null) return TrafficDriving.reachRadius;
  final angle = network.turnAngle(car.fromNodeId, car.toNodeId, next);
  // Разворот вписывает отдельный режим (см. uTurnMinRadius) — тут просто
  // доехать до конца полосы.
  if (angle > 2.6) return TrafficDriving.reachRadius;
  return math.max(1.0, TrafficDriving.minTurnRadius * math.tan(angle / 2));
}

/// Точка преследования на линии полосы текущего ребра: проекция машины
/// плюс упреждение, растущее со скоростью, но не дальше конца ребра.
vm.Vector3 _aimPoint(TrafficNetwork network, TrafficCar car, vm.Vector3 laneEnd) {
  final direction = _edgeDirection(network, car.fromNodeId, car.toNodeId);
  if (direction == null) return laneEnd;
  final ahead = (laneEnd - car.position).dot(direction);
  final lookAhead = math.max(6.0, car.speed * 1.2);
  if (ahead <= lookAhead) return laneEnd;
  return laneEnd - direction * (ahead - lookAhead);
}

vm.Vector3? _edgeDirection(TrafficNetwork network, String from, String to) {
  final a = network.graph.nodes[from];
  final b = network.graph.nodes[to];
  if (a == null || b == null) return null;
  final d = vm.Vector3(b.x - a.x, 0, b.z - a.z);
  final length = d.length;
  return length < 1e-6 ? null : d / length;
}

double _wrapAngle(double angle) => (angle + math.pi) % (2 * math.pi) - math.pi;
