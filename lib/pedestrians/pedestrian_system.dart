import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../weapons/ballistics.dart';
import '../weapons/player_shooting.dart';
import '../world/road_graph.dart';
import 'pedestrian.dart';

/// Пуля попала в пешехода (см. PedestrianSystem.raycastShootable).
typedef PedestrianShotHit = ({int index, double distance, BodyZone zone});

/// Держит NPC-пешеходов вокруг игрока/машины: спавнит рядом
/// ([spawnRadius]), переселяет в кольцо [minRespawnDistance]..[spawnRadius],
/// когда отходят дальше [despawnRadius], двигает по дорожному графу (см. pedestrian.dart —
/// сама ходьба протестирована юнит-тестом отдельно от рендера).
///
/// Рендер — один общий `InstancedMesh` на всех пешеходов (капсулы, как у
/// игрока, только меньше и разного цвета) — один draw call независимо от
/// [population]. НЕ используется built-in `ThirdPersonControllerComponent`
/// с его ground-рейкастами: у дорожного графа уже есть точная высота узлов
/// (все ~0, ровная земля), рейкастить незачем — а с N пешеходов это было
/// бы N лишних raycastNode на кадр, ровно та проблема с лагами, что
/// разбирали на Android этим утром (см. PROGRESS.md).
class PedestrianSystem implements ShootTargets {
  PedestrianSystem({
    required this.graph,
    required this.raycastRoot,
    this.population = 16,
    this.spawnRadius = 120.0,
    this.despawnRadius = 180.0,
    this.minRespawnDistance = 70.0,
    this.walkSpeed = 1.3,
    math.Random? random,
  }) : adjacency = buildPedestrianAdjacency(graph),
       _random = random ?? math.Random(),
       bodies = InstancedMesh(
         geometry: CapsuleGeometry(radius: _radius, height: _bodyHeight),
         material: PhysicallyBasedMaterial()
           ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
           ..roughnessFactor = 0.85,
       );

  static const double _radius = 0.3;
  static const double _bodyHeight = 0.9;
  static const double _totalHeight = _bodyHeight + _radius * 2;

  static final List<vm.Vector4> _palette = [
    vm.Vector4(0.25, 0.35, 0.75, 1.0), // синий
    vm.Vector4(0.85, 0.70, 0.20, 1.0), // жёлтый
    vm.Vector4(0.55, 0.30, 0.65, 1.0), // фиолетовый
    vm.Vector4(0.20, 0.55, 0.50, 1.0), // бирюзовый
    vm.Vector4(0.80, 0.45, 0.20, 1.0), // оранжевый
  ];

  final RoadGraph graph;

  /// Узел, от которого рейкастятся рёбра графа на препятствия (см.
  /// _isEdgePassable) — сцена целиком, не привязан к конкретному чанку:
  /// нужный чанк должен быть уже загружен к тому моменту, когда пешеход
  /// реально собирается пройти по этому ребру (в радиусе видимости).
  final Node raycastRoot;

  final Map<String, List<String>> adjacency;
  final int population;
  final double spawnRadius;
  final double despawnRadius;
  final double minRespawnDistance;
  final double walkSpeed;
  final InstancedMesh bodies;

  final math.Random _random;
  final List<Pedestrian> _pedestrians = [];
  bool _spawned = false;

  /// Пешеход раньше шёл по прямой между узлами графа без проверки на
  /// препятствия — иногда это резало угол здания (см. PROGRESS.md).
  /// Множество РЁБЕР С ПОДТВЕРЖДЁННОЙ блокировкой — не кэш "проходимо/нет"
  /// целиком: чанки района грузятся асинхронно, и на старте здание могло
  /// ещё не подгрузиться к моменту первой проверки (баг, из-за которого
  /// кэш "true" был бы неверным навсегда). "Открыто" просто перепроверяется
  /// каждый раз — не каждый кадр (только когда пешеход выбирает это ребро
  /// целью), суммарно на порядки дешевле, чем N живых ground-рейкастов на
  /// кадр (см. doc-комментарий класса).
  final Set<String> _blockedEdges = {};

  static const double _eyeHeight = 1.0;

  /// Ниже которой наезд машиной не считается — стоящая/едва катящаяся
  /// машина у пешехода не в счёт, только реальный удар.
  static const double hitSpeedThreshold = 3.0;
  static const double _hitRadius = 1.0;

  Node buildNode() => Node()..addComponent(InstancedMeshComponent(bodies));

  /// Позиции пешеходов — перед ними тормозит трафик (см. lib/traffic/).
  Iterable<vm.Vector3> get positions => _pedestrians.map((p) => p.position);

  /// Радиус капсулы пешехода — для препятствий трафика.
  static const double bodyRadius = _radius;

  /// Полный рост пешехода — для попаданий и автоприцела.
  static const double bodyHeight = _totalHeight;

  /// Тело убитого убирается (пешеход переселяется), только если лежит
  /// дольше этого и игрок не ближе [_bodyCleanupDistance] — на глазах
  /// трупы не исчезают.
  static const double _bodyCleanupSeconds = 45.0;
  static const double _bodyCleanupDistance = 60.0;

  /// Пуля по лучу: ближайший живой стоящий пешеход, в которого попадает
  /// луч из [origin] вдоль единичного [direction] не дальше [maxDistance].
  @override
  PedestrianShotHit? raycastShootable(vm.Vector3 origin, vm.Vector3 direction, double maxDistance) {
    PedestrianShotHit? best;
    for (var i = 0; i < _pedestrians.length; i++) {
      final pedestrian = _pedestrians[i];
      if (!pedestrian.isShootable) continue;
      final limit = best?.distance ?? maxDistance;
      final t = rayVerticalCapsule(origin, direction, limit, pedestrian.position, _radius, _totalHeight);
      if (t == null) continue;
      final hitY = origin.y + direction.y * t;
      best = (index: i, distance: t, zone: zoneForHitHeight(hitY - pedestrian.position.y, _totalHeight));
    }
    return best;
  }

  /// Пуля попала в пешехода [index]: урон [damage] от стрелка в [from].
  /// Возвращает true, если убит.
  @override
  bool applyShot(int index, double damage, vm.Vector3 from) {
    final pedestrian = _pedestrians[index];
    final killed = pedestrian.takeDamage(damage, from);
    if (!killed) pedestrian.scare(from, graph);
    bodies.setInstanceTransform(pedestrian.instanceIndex, _instanceTransform(pedestrian));
    return killed;
  }

  /// Выстрел в [shooter] слышно на [radius] метров: все живые рядом
  /// бегут прочь. Возвращает, сколько было свидетелей.
  @override
  int scareAround(vm.Vector3 shooter, double radius) {
    final radiusSq = radius * radius;
    var witnesses = 0;
    for (final pedestrian in _pedestrians) {
      if (pedestrian.isDead || (pedestrian.position - shooter).length2 > radiusSq) continue;
      pedestrian.scare(shooter, graph);
      witnesses++;
    }
    return witnesses;
  }

  /// Точки прицеливания (грудь) живых стоящих пешеходов — для
  /// автоприцела. [indices] получает их номера для [applyShot].
  @override
  void collectAimPoints(List<vm.Vector3> points, List<int> indices) {
    for (var i = 0; i < _pedestrians.length; i++) {
      final pedestrian = _pedestrians[i];
      if (!pedestrian.isShootable) continue;
      points.add(pedestrian.position + vm.Vector3(0, _totalHeight * 0.65, 0));
      indices.add(i);
    }
  }

  /// Материал для [buildDebugTargetLinesNode] — ярко-розовый, не пересекается
  /// с жёлтыми линиями дорожного графа (см. road_graph.dart), чтобы оба
  /// debug-слоя можно было включить одновременно и не путать линии.
  static final Material _debugLineMaterial = UnlitMaterial()
    ..baseColorFactor = vm.Vector4(1.0, 0.15, 0.85, 1.0);

  /// Отладочная визуализация — ровно тот отрезок ребра графа (от узла до
  /// узла, на высоте [_eyeHeight]), который проверяет [_isEdgePassable].
  /// Рисуется именно ребро, а не линия от текущей позиции пешехода: смысл
  /// в том, чтобы увидеть глазами, что именно тестирует рейкаст, когда
  /// пешеход всё равно проходит сквозь стену — предыдущие два фикса (кэш
  /// блокировки, фильтр типов highway) не помогли, и остаётся непроверенным,
  /// попадает ли рейкаст в геометрию вообще (см. BUGS.md). Включается извне
  /// (см. Game.debugShowRoadGraph), не часть обычного игрового рендера.
  Node buildDebugTargetLinesNode() => Node();

  /// Рёбра, по которым построен текущий debug-меш — чтобы не пересобирать его
  /// каждый кадр: конструктор LineSegmentsGeometry заводит device buffer на
  /// GPU, и покадровая пересборка = 60 новых буферов в секунду на ровном
  /// месте. Набор рёбер меняется редко (только когда пешеход дошёл до узла и
  /// выбрал новую цель), так что сравнение состава — точный признак того,
  /// что меш пора перестроить.
  final List<String> _debugFromIds = [];
  final List<String> _debugToIds = [];

  void updateDebugTargetLines(Node node) {
    if (!_debugEdgesChanged()) return;

    _debugFromIds.clear();
    _debugToIds.clear();
    final positions = Float32List(_pedestrians.length * 6);
    var i = 0;
    for (final pedestrian in _pedestrians) {
      _debugFromIds.add(pedestrian.currentNodeId);
      _debugToIds.add(pedestrian.targetNodeId);
      final from = graph.nodes[pedestrian.currentNodeId];
      final to = graph.nodes[pedestrian.targetNodeId];
      if (from == null || to == null) continue;
      positions[i++] = from.x;
      positions[i++] = _eyeHeight;
      positions[i++] = from.z;
      positions[i++] = to.x;
      positions[i++] = _eyeHeight;
      positions[i++] = to.z;
    }
    node.mesh = i == 0
        ? null
        : Mesh(
            LineSegmentsGeometry(LineSegmentData(positions: positions.sublist(0, i)), width: 0.2),
            _debugLineMaterial,
          );
  }

  bool _debugEdgesChanged() {
    if (_debugFromIds.length != _pedestrians.length) return true;
    for (var i = 0; i < _pedestrians.length; i++) {
      if (_debugFromIds[i] != _pedestrians[i].currentNodeId ||
          _debugToIds[i] != _pedestrians[i].targetNodeId) {
        return true;
      }
    }
    return false;
  }

  /// Зовётся каждый кадр из Game.tick(). Первый вызов лениво спавнит
  /// начальную популяцию вокруг [trackedPosition] — раньше нельзя, узлы
  /// графа сами по себе не знают, где стартует игрок. [vehiclePosition]/
  /// [vehicleSpeed] — если заданы (машина существует и её скорость выше
  /// [hitSpeedThreshold]), пешеходы в радиусе удара падают (см.
  /// Pedestrian.knockDown) и засчитываются в возвращаемое число наездов —
  /// на нём строится WantedSystem (см. lib/police).
  int update(
    double dt,
    vm.Vector3 trackedPosition, {
    vm.Vector3? vehiclePosition,
    double vehicleSpeed = 0.0,
  }) {
    if (!_spawned) {
      _spawnInitialPopulation(trackedPosition);
      _spawned = true;
    }

    var hits = 0;
    final canHit = vehiclePosition != null && vehicleSpeed >= hitSpeedThreshold;
    final hitRadiusSq = _hitRadius * _hitRadius;
    final despawnRadiusSq = despawnRadius * despawnRadius;
    for (final pedestrian in _pedestrians) {
      final arrived = advancePedestrian(
        pedestrian,
        graph,
        adjacency,
        dt: dt,
        speed: walkSpeed,
        random: _random,
      );
      if (arrived) _ensurePassableTarget(pedestrian);

      // Лежачего (и мёртвого) повторно не сбить и не засчитать второй раз
      // в розыск.
      if (canHit &&
          !pedestrian.isKnockedDown &&
          !pedestrian.isDead &&
          (pedestrian.position - vehiclePosition).length2 <= hitRadiusSq) {
        hits++;
        pedestrian.knockDown(vehiclePosition, vehicleSpeed);
      } else if ((pedestrian.position - trackedPosition).length2 > despawnRadiusSq) {
        _respawnNear(pedestrian, trackedPosition);
      } else if (pedestrian.isDead &&
          pedestrian.deadSeconds > _bodyCleanupSeconds &&
          (pedestrian.position - trackedPosition).length2 > _bodyCleanupDistance * _bodyCleanupDistance) {
        _respawnNear(pedestrian, trackedPosition);
      }

      bodies.setInstanceTransform(pedestrian.instanceIndex, _instanceTransform(pedestrian));
    }
    return hits;
  }

  /// Стоящий — капсула вертикально по курсу; сбитый или убитый — лежит на земле
  /// вдоль направления отлёта (поворот на 90° вокруг своей поперечной оси).
  vm.Matrix4 _instanceTransform(Pedestrian pedestrian) {
    final heading = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), pedestrian.yaw);
    if (!pedestrian.isKnockedDown && !pedestrian.isDead) {
      return vm.Matrix4.compose(
        pedestrian.position + vm.Vector3(0, _totalHeight / 2, 0),
        heading,
        vm.Vector3.all(1.0),
      );
    }
    return vm.Matrix4.compose(
      pedestrian.position + vm.Vector3(0, _radius, 0),
      heading * vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
      vm.Vector3.all(1.0),
    );
  }

  void _spawnInitialPopulation(vm.Vector3 center) {
    for (var i = 0; i < population; i++) {
      final pedestrian = _createAt(_randomWalkableNodeNear(center));
      pedestrian.instanceIndex = bodies.addInstance(
        vm.Matrix4.compose(
          pedestrian.position + vm.Vector3(0, _totalHeight / 2, 0),
          vm.Quaternion.identity(),
          vm.Vector3.all(1.0),
        ),
        color: _palette[_random.nextInt(_palette.length)],
      );
      _pedestrians.add(pedestrian);
    }
  }

  /// Водитель угнанной машины выскакивает в [door] и в панике бежит к
  /// ближайшему узлу пешеходного графа, а оттуда дальше по графу — прочь
  /// от [awayFrom] (игрока), если есть выбор. Отдельного NPC не заводим:
  /// популяция фиксирована, так что "водителем" становится самый дальний
  /// от места пешеход (его исчезновение вдали никто не видит).
  void spawnFleeingDriver(vm.Vector3 door, vm.Vector3 awayFrom) {
    if (_pedestrians.isEmpty) return;
    Pedestrian? farthest;
    var farthestSq = -1.0;
    for (final pedestrian in _pedestrians) {
      final distanceSq = (pedestrian.position - door).length2;
      if (distanceSq > farthestSq) {
        farthestSq = distanceSq;
        farthest = pedestrian;
      }
    }
    final driver = farthest!;

    final start = _nearestWalkableNode(door);
    final neighbors = adjacency[start.id] ?? const <String>[];
    var target = neighbors.isEmpty ? start.id : neighbors.first;
    var bestScore = double.negativeInfinity;
    for (final id in neighbors) {
      final node = graph.nodes[id];
      if (node == null) continue;
      final score = (node.toVector3() - awayFrom).length2;
      if (score > bestScore) {
        bestScore = score;
        target = id;
      }
    }

    driver
      ..position = door.clone()
      ..currentNodeId = start.id
      ..targetNodeId = target
      ..returnPoint = start.toVector3()
      ..knockedDownSeconds = 0.0
      ..panicSeconds = 8.0
      ..fleeFrom = awayFrom.clone()
      ..revive();
  }

  RoadGraphNode _nearestWalkableNode(vm.Vector3 position) {
    RoadGraphNode? best;
    var bestSq = double.infinity;
    for (final node in graph.nodes.values) {
      if (adjacency[node.id]?.isEmpty ?? true) continue;
      final distanceSq = (node.toVector3() - position).length2;
      if (distanceSq < bestSq) {
        bestSq = distanceSq;
        best = node;
      }
    }
    return best!;
  }

  /// Ушедший за [despawnRadius] пешеход переселяется — но не куда попало в
  /// [spawnRadius], а в кольцо от [minRespawnDistance]: раньше он мог
  /// возникнуть прямо перед игроком из воздуха. Камера здесь сознательно не
  /// участвует (существование агентов — только по расстоянию, см.
  /// PROGRESS.md, "Принцип, который нельзя нарушать").
  void _respawnNear(Pedestrian pedestrian, vm.Vector3 center) {
    final fresh = _createAt(_randomWalkableNodeNear(center, minDistance: minRespawnDistance));
    pedestrian
      ..position = fresh.position
      ..currentNodeId = fresh.currentNodeId
      ..targetNodeId = fresh.targetNodeId
      ..knockedDownSeconds = 0.0
      ..panicSeconds = 0.0
      ..fleeFrom = null
      ..returnPoint = null
      ..revive();
  }

  Pedestrian _createAt(RoadGraphNode node) {
    final neighbors = adjacency[node.id] ?? const <String>[];
    final target = neighbors.isNotEmpty ? neighbors[_random.nextInt(neighbors.length)] : node.id;
    final pedestrian = Pedestrian(position: node.toVector3(), currentNodeId: node.id, targetNodeId: target);
    _ensurePassableTarget(pedestrian);
    return pedestrian;
  }

  /// Если текущая цель пешехода режет угол здания (см. doc-комментарий
  /// [_blockedEdges]), перебирает соседей узла в поисках проходимого —
  /// до 5 попыток, дальше просто оставляет как есть (все соседи узла
  /// перекрыты — редкий крайний случай, не стоит зацикливаться).
  void _ensurePassableTarget(Pedestrian pedestrian) {
    var attempts = 0;
    while (!_isEdgePassable(pedestrian.currentNodeId, pedestrian.targetNodeId) && attempts < 5) {
      final neighbors = adjacency[pedestrian.currentNodeId];
      if (neighbors == null || neighbors.isEmpty) return;
      pedestrian.targetNodeId = neighbors[_random.nextInt(neighbors.length)];
      attempts++;
    }
  }

  bool _isEdgePassable(String fromId, String toId) {
    final key = fromId.compareTo(toId) <= 0 ? '$fromId|$toId' : '$toId|$fromId';
    // Кэшируем ТОЛЬКО подтверждённую блокировку, не "проходимо" — чанки
    // района грузятся асинхронно (см. DistrictStreamer), и на самом старте
    // раньше могло не найтись здание просто потому, что его чанк ещё не
    // успел прогрузиться; закэшированное "true" тогда навсегда пряталось
    // бы от реального рейкаста после дозагрузки (баг, замечен
    // пользователем — пешеходы всё равно проходили сквозь дома). "Открыто"
    // просто перепроверяется каждый раз — это не каждый кадр (только когда
    // пешеход выбирает это ребро целью), суммарно на порядки дешевле.
    if (_blockedEdges.contains(key)) return false;

    final from = graph.nodes[fromId];
    final to = graph.nodes[toId];
    if (from == null || to == null || fromId == toId) return true;

    final origin = from.toVector3(y: _eyeHeight);
    final delta = to.toVector3(y: _eyeHeight) - origin;
    final distance = delta.length;
    // Чуть недолетаем до цели: сама конечная точка иногда лежит впритык
    // к стене (узел на углу дома), не должна давать ложный "перекрыто".
    final blocked = distance >= 0.5 &&
        raycastNode(raycastRoot, vm.Ray.originDirection(origin, delta), maxDistance: distance - 0.5) !=
            null;
    if (blocked) _blockedEdges.add(key);
    return !blocked;
  }

  /// Только узлы с хотя бы одним соседом — иначе пешеход появится и сразу
  /// встанет колом (см. advancePedestrian: без соседей цель = сам узел).
  ///
  /// [minDistance] > 0 — только узлы не ближе него (кольцо); если в кольце
  /// узлов нет, годится любой в [spawnRadius].
  RoadGraphNode _randomWalkableNodeNear(vm.Vector3 center, {double minDistance = 0.0}) {
    final nearby = <RoadGraphNode>[];
    final ring = <RoadGraphNode>[];
    final radiusSq = spawnRadius * spawnRadius;
    final minSq = minDistance * minDistance;
    for (final node in graph.nodes.values) {
      if (adjacency[node.id]?.isEmpty ?? true) continue;
      final distanceSq = (node.toVector3() - center).length2;
      if (distanceSq > radiusSq) continue;
      nearby.add(node);
      if (distanceSq >= minSq) ring.add(node);
    }
    if (ring.isNotEmpty) return ring[_random.nextInt(ring.length)];
    if (nearby.isNotEmpty) return nearby[_random.nextInt(nearby.length)];

    // Игрок дальше spawnRadius от любой дороги (внутри двора/дома) —
    // берём ближайший ходибельный узел графа вообще, не разброс по радиусу.
    final walkable = graph.nodes.values.where((n) => adjacency[n.id]?.isNotEmpty ?? false).toList();
    walkable.sort(
      (a, b) => (a.toVector3() - center).length2.compareTo((b.toVector3() - center).length2),
    );
    return walkable.first;
  }
}
