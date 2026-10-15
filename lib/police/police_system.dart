import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../vehicles/vehicle.dart';
import '../vehicles/vehicle_spec.dart';
import '../world/road_graph.dart';
import 'police_car.dart';
import '../characters/character_library.dart';
import 'police_officers.dart';
import 'road_pathfinding.dart';
import 'wanted_state.dart';

/// Одна активная патрульная машина + её AI-состояние (текущий путь по
/// дорожному графу и таймер до перерасчёта). Путь хранит id узлов
/// ВПЕРЕДИ машины (текущий узел уже не включён — см. PoliceSystem._repath).
class _PoliceUnit {
  _PoliceUnit(this.vehicle, this.id);

  final BuiltVehicle vehicle;
  final int id;
  final List<String> path = [];
  double repathTimer = 0.0;

  /// Офицеры вышли — машина стоит, пока их не заберёт.
  bool deployed = false;

  /// Сколько секунд после отзыва офицеров не высаживать снова — иначе
  /// машина рядом с игроком высаживала бы их каждый кадр.
  double redeployCooldown = 0.0;

  final StuckRecovery stuck = StuckRecovery();

  /// Маршрут по дорогам кончился — машина у ближайшего к игроку узла
  /// графа. Если игрок всё ещё далеко (двор, парк), ближе по дорогам не
  /// подъехать: при вооружённом розыске пора высаживаться.
  bool reachedRoadEnd = false;

  /// Где машина была, когда последний раз заметно сдвинулась, и сколько
  /// секунд с тех пор топчется на месте (дёргается у стены, сдаёт назад
  /// и снова упирается) — для пересоздания безнадёжно застрявшей. Не
  /// "не приближается к игроку": путь часто сначала уводит в объезд.
  vm.Vector3? anchor;
  double stalledSeconds = 0.0;
}

/// Запасные числа вождения патрульной машины — если в assets/data/
/// vehicles.json почему-то нет car_police_01 (см. _fallbackSpec в
/// vehicle.dart — тот же приём для машины игрока).
const _fallbackPoliceSpec = VehicleSpec(maxSpeedKmh: 190.0, acceleration: 15.0, braking: 30.0);

/// Полицейские машины, которые появляются при розыске (см. WantedState) и
/// едут к игроку по дорожному графу (см. road_pathfinding.dart) — не
/// прямой линией, чтобы не резать здания, но и не полноценный A* с учётом
/// трафика (граф маленький, ~700 узлов, Дейкстра дёшева, см.
/// findShortestPath). Контакт с игроком на [arrestRadius] дольше
/// [arrestHoldSeconds] — арест (см. Game.tick).
///
/// Число активных машин = min(звёзды, [maxUnits]) — двух достаточно, чтобы
/// погоня читалась, и не добавляет заметной нагрузки на слабый Android
/// поверх уже больной FPS-картины (см. PROGRESS.md, "Диагностика лагов").
class PoliceSystem {
  PoliceSystem._({
    required this.graph,
    required this.scene,
    required VehicleSpec policeSpec,
    bool Function(vm.Vector3 a, vm.Vector3 b)? edgeIsClear,
    math.Random? random,
    PoliceOfficers? officers,
  }) : adjacency = buildVehicleAdjacency(graph, edgeIsClear: edgeIsClear),
      officers = officers ?? PoliceOfficers(),
      _policeSpec = policeSpec,
      _random = random ?? math.Random();

  /// Спека грузится один раз здесь (асинхронно, во время Game.load()) —
  /// сам спавн машины внутри update() синхронный (buildVehicleWithSpec, а
  /// не buildVehicle), потому что update() зовётся каждый кадр из
  /// Game.tick(), который не async.
  static Future<PoliceSystem> create({
    required RoadGraph graph,
    required Scene scene,
    bool Function(vm.Vector3 a, vm.Vector3 b)? edgeIsClear,
    math.Random? random,
    CharacterLibrary? characters,
  }) async {
    final spec = await loadVehicleSpec('car_police_01') ?? _fallbackPoliceSpec;
    return PoliceSystem._(
      graph: graph,
      scene: scene,
      policeSpec: spec,
      edgeIsClear: edgeIsClear,
      random: random,
      officers: PoliceOfficers(characters: characters),
    );
  }

  final RoadGraph graph;
  final Scene scene;
  final Map<String, List<String>> adjacency;
  final VehicleSpec _policeSpec;
  final math.Random _random;

  static const int maxUnits = 2;
  static const double repathIntervalSeconds = 2.5;
  static const double waypointReachRadius = 4.0;
  static const double spawnMinDistance = 55.0;
  static const double spawnMaxDistance = 90.0;
  static const double arrestRadius = 4.0;
  static const double arrestHoldSeconds = 2.0;

  final List<_PoliceUnit> _units = [];
  double _arrestTimer = 0.0;
  int _nextUnitId = 0;
  double _lastDt = 0.0;
  final List<_PoliceUnit> _hopeless = [];
  Iterable<vm.Vector3> _blockers = const [];

  /// Полицейские пешком (см. police_officers.dart).
  final PoliceOfficers officers;

  /// С этого уровня полиция не задерживает, а применяет оружие: машина,
  /// догнав игрока, останавливается и высаживает офицеров.
  static const int armedResponseStars = 2;

  /// Ближе этого машина тормозит и высаживает офицеров.
  static const double deployDistance = 18.0;

  /// Офицеров забирают, если игрок ушёл от машины дальше этого или все
  /// живые не видят его дольше [_lostSightSeconds].
  static const double _recallDistance = 70.0;
  static const double _lostSightSeconds = 8.0;

  /// Машина, вставшая ближе этого к игроку (ближе не подъехать — игрок во
  /// дворе или в парке), высаживает офицеров.
  static const double _deployOnFootDistance = 70.0;

  /// Машина за столько секунд не сдвинулась дальше [_stallMoveMeters]
  /// (выбирание задним ходом не помогло) и сама вне кадра — пересоздаётся
  /// на новом месте.
  static const double _respawnAfterStalledSeconds = 8.0;
  static const double _stallMoveMeters = 4.0;
  static const double _respawnMinDistance = 75.0;

  /// Узлы живых патрульных машин — чтобы игрок пешком не проходил сквозь
  /// них: коллизионная область персонажа собирается из ближних чанков
  /// района, а машины в чанки не входят (см. CharacterCollisionField).
  Iterable<Node> get unitNodes => _units.map((unit) => unit.vehicle.node);

  /// Зовётся каждый кадр из Game.tick(). Возвращает true ровно в кадр,
  /// когда игрок только что оказался пойман (машина рядом [arrestHoldSeconds]
  /// подряд) — Game сбрасывает розыск/телепортирует игрока в ответ.
  ///
  /// [blockers] — машины трафика: застрявшая за ними полиция объезжает
  /// их по встречке (см. isBlockedAhead).
  bool update(double dt, vm.Vector3 targetPosition, {Iterable<vm.Vector3> blockers = const []}) {
    _lastDt = dt;
    _blockers = blockers;
    final desired = wantedState.stars == 0 ? 0 : math.min(wantedState.stars, maxUnits);
    _syncUnitCount(desired, targetPosition);
    final armed = wantedState.stars >= armedResponseStars;

    var anyClose = false;
    for (final unit in _units) {
      final carPos = unit.vehicle.node.globalTransform.getTranslation();
      final distance = (carPos - targetPosition).length;
      unit.redeployCooldown = math.max(0.0, unit.redeployCooldown - dt);

      if (unit.deployed) {
        _holdStill(unit);
        final recall =
            officers.aliveCount(unit.id) == 0 ||
            distance > _recallDistance ||
            officers.lostSight(unit.id, _lostSightSeconds) ||
            !armed;
        if (recall) {
          officers.recall(unit.id);
          unit
            ..deployed = false
            ..redeployCooldown = 6.0
            ..path.clear();
        }
        continue;
      }

      final anchor = unit.anchor;
      if (anchor == null || (carPos - anchor).length > _stallMoveMeters) {
        unit
          ..anchor = carPos.clone()
          ..stalledSeconds = 0.0;
      } else {
        unit.stalledSeconds += dt;
      }

      final cannotGetCloser = distance <= _deployOnFootDistance && unit.reachedRoadEnd;
      if (armed && unit.redeployCooldown == 0.0 && (distance <= deployDistance || cannotGetCloser)) {
        // Сначала тормозим, высаживаемся — уже почти стоя.
        _holdStill(unit);
        if (unit.vehicle.controller.speed < 2.0) {
          unit.deployed = officers.deploy(unit.id, carPos, unit.vehicle.controller.heading) > 0;
        }
        continue;
      }

      unit.repathTimer -= dt;
      // ИЛИ, не И: путь пуст — строим немедленно, иначе перестраиваем раз в
      // repathIntervalSeconds вслед за уехавшим игроком. С `&&` перерасчёт
      // случался только после того, как машина израсходует весь старый
      // маршрут — то есть патруль ехал туда, где игрок был в момент первого
      // расчёта, и оторваться от погони было слишком легко. Таймер взводится
      // внутри условия (в том числе когда _repath не нашёл путь) — иначе при
      // недостижимой цели Дейкстра считалась бы каждый кадр.
      if (unit.path.isEmpty || unit.repathTimer <= 0) {
        _repath(unit, carPos, targetPosition);
        unit.repathTimer = repathIntervalSeconds;
      }
      _followPath(unit, carPos, targetPosition);

      // Задерживают только при лёгком розыске — дальше стреляют.
      if (!armed && distance <= arrestRadius) anyClose = true;

      if (unit.stalledSeconds >= _respawnAfterStalledSeconds && distance >= _respawnMinDistance) {
        _hopeless.add(unit);
      }
    }
    for (final unit in _hopeless) {
      _units.remove(unit);
      scene.remove(unit.vehicle.node);
    }
    _hopeless.clear(); // недостающие машины досоздаст _syncUnitCount в следующем кадре

    if (anyClose) {
      _arrestTimer += dt;
      if (_arrestTimer >= arrestHoldSeconds) {
        _arrestTimer = 0.0;
        return true;
      }
    } else {
      _arrestTimer = 0.0;
    }
    return false;
  }

  /// Немедленно убирает всех патрульных со сцены — зовётся Game-ом сразу
  /// после ареста (в GTA полиция не продолжает стоять рядом на экране
  /// "задержан"), не через постепенное угасание по звёздам.
  void clearUnits() {
    for (final unit in _units) {
      scene.remove(unit.vehicle.node);
    }
    _units.clear();
    officers.clear();
    _arrestTimer = 0.0;
  }

  /// Тормозить до полной остановки и стоять. Газ против хода: при ходе
  /// вперёд минус-газ — тормоз, но при ходе назад он разгонял бы назад.
  void _holdStill(_PoliceUnit unit) {
    final controller = unit.vehicle.controller;
    final heading = controller.heading;
    final forwardSpeed = controller.velocityXZ.x * math.sin(heading) + controller.velocityXZ.y * math.cos(heading);
    final throttle = forwardSpeed > 0.5 ? -1.0 : (forwardSpeed < -0.5 ? 1.0 : 0.0);
    controller.setInput(throttle: throttle, steer: 0.0);
  }

  void _syncUnitCount(int desired, vm.Vector3 targetPosition) {
    while (_units.length < desired) {
      final unit = _spawnUnit(targetPosition);
      if (unit == null) break; // негде заспавнить — не зацикливаемся
      _units.add(unit);
    }
    while (_units.length > desired) {
      final unit = _units.removeLast();
      officers.recall(unit.id);
      scene.remove(unit.vehicle.node);
    }
  }

  _PoliceUnit? _spawnUnit(vm.Vector3 targetPosition) {
    final spawnNode = _pickSpawnNode(targetPosition);
    if (spawnNode == null) return null;

    final vehicle = buildVehicleWithSpec(VehicleArchetype.police, _policeSpec, attachPlayerInput: false);
    vehicle.node.position = spawnNode.toVector3();
    vehicle.node.add(_buildLightBar());
    scene.add(vehicle.node);
    return _PoliceUnit(vehicle, _nextUnitId++);
  }

  /// Светобалка на крыше — единственный визуальный признак "это полиция"
  /// (сам силуэт/цвет кузова — VehicleArchetype.police, см. vehicle.dart).
  /// Статичная (не мигает) — анимация цвета каждый кадр на N машинах это
  /// лишняя работа ради эффекта, который не стоит того на слабом железе.
  Node _buildLightBar() {
    final dims = VehicleArchetype.police;
    final roofY = dims.wheelRadius + dims.chassisHeight + dims.cabinHeight;
    final barY = roofY + 0.06;
    final barWidth = dims.cabinWidth * 0.9;

    final bar = Node();
    final red = Node(
      mesh: Mesh(
        CuboidGeometry(vm.Vector3(barWidth / 2, 0.12, 0.3)),
        _lightBarMaterial(vm.Vector4(0.9, 0.05, 0.05, 1.0)),
      ),
    )..position = vm.Vector3(-barWidth / 4, barY, dims.cabinZOffset);
    final blue = Node(
      mesh: Mesh(
        CuboidGeometry(vm.Vector3(barWidth / 2, 0.12, 0.3)),
        _lightBarMaterial(vm.Vector4(0.05, 0.15, 0.9, 1.0)),
      ),
    )..position = vm.Vector3(barWidth / 4, barY, dims.cabinZOffset);
    bar
      ..add(red)
      ..add(blue);
    return bar;
  }

  PhysicallyBasedMaterial _lightBarMaterial(vm.Vector4 color) => PhysicallyBasedMaterial()
    ..baseColorFactor = color
    ..emissiveFactor = color
    ..emissiveStrength = 3.0
    ..roughnessFactor = 0.4;

  void _repath(_PoliceUnit unit, vm.Vector3 carPos, vm.Vector3 targetPosition) {
    final startId = nearestVehicleNodeId(graph, adjacency, carPos);
    final goalId = nearestVehicleNodeId(graph, adjacency, targetPosition);
    if (startId == null || goalId == null) return;

    final path = findShortestPath(graph, adjacency, startId, goalId);
    if (path == null) return;

    unit.path
      ..clear()
      ..addAll(path.skip(1)); // текущий узел не нужен как путевая точка
    unit.reachedRoadEnd = unit.path.isEmpty;
  }

  void _followPath(_PoliceUnit unit, vm.Vector3 carPos, vm.Vector3 targetPosition) {
    while (unit.path.isNotEmpty) {
      final waypoint = graph.nodes[unit.path.first];
      if (waypoint == null) {
        unit.path.removeAt(0);
        continue;
      }
      final waypointPos = waypoint.toVector3();
      if ((waypointPos - carPos).length <= waypointReachRadius) {
        unit.path.removeAt(0);
        continue;
      }
      final input = computePoliceInput(
        position: carPos,
        heading: unit.vehicle.controller.heading,
        targetPosition: _steerTarget(unit, carPos, waypointPos),
      );
      // Крутой поворот после этой точки — тормозим заранее.
      var turnAngle = 0.0;
      if (unit.path.length > 1) {
        final next = graph.nodes[unit.path[1]];
        if (next != null) {
          final approach = waypointPos - carPos;
          final leave = next.toVector3() - waypointPos;
          if (approach.length2 > 1e-6 && leave.length2 > 1e-6) {
            turnAngle = math.acos(approach.normalized().dot(leave.normalized()).clamp(-1.0, 1.0));
          }
        }
      }
      final throttle = cornerThrottle(
        baseThrottle: input.throttle,
        speed: unit.vehicle.controller.speed,
        distanceToWaypoint: (waypointPos - carPos).length,
        turnAngle: turnAngle,
      );
      _drive(unit, throttle, input.steer);
      return;
    }

    unit.reachedRoadEnd = true;
    // Путь закончился (доехали до последней путевой точки, но, возможно,
    // ещё не вплотную к игроку — цель двигалась, пока машина ехала) — рулим
    // напрямую на игрока до следующего пересчёта пути.
    final input = computePoliceInput(
      position: carPos,
      heading: unit.vehicle.controller.heading,
      targetPosition: _steerTarget(unit, carPos, targetPosition),
    );
    _drive(unit, input.throttle, input.steer);
  }

  /// Куда рулить: прямо на [target] или в объезд машины впереди.
  vm.Vector3 _steerTarget(_PoliceUnit unit, vm.Vector3 carPos, vm.Vector3 target) {
    final others = _blockers.followedBy(
      _units.where((u) => u != unit).map((u) => u.vehicle.node.globalTransform.getTranslation()),
    );
    if (!isBlockedAhead(carPos, unit.vehicle.controller.heading, others)) return target;
    return overtakeTarget(carPos, target);
  }

  /// Газ/руль AI с выбиранием из тупика: упёрлась — сдаёт назад с
  /// обратным рулём (нос разворачивается к цели), потом снова вперёд.
  void _drive(_PoliceUnit unit, double throttle, double steer) {
    final controller = unit.vehicle.controller;
    if (unit.stuck.update(_lastDt, speed: controller.speed, wantsToMove: throttle > 0.0)) {
      controller.setInput(throttle: -1.0, steer: -steer);
      return;
    }
    controller.setInput(throttle: throttle, steer: steer);
  }

  /// Узел дорожного графа в кольце [spawnMinDistance]..[spawnMaxDistance] от
  /// игрока — вне поля зрения, но не через полкарты. Если в кольце нет
  /// проезжих узлов (игрок у края района), берёт ближайший проезжий узел
  /// вообще — лучше заспавнить чуть ближе, чем не заспавнить совсем.
  RoadGraphNode? _pickSpawnNode(vm.Vector3 targetPosition) {
    // Сначала обычное кольцо; если от всех его узлов до игрока только
    // огромные петли (так у спавна: 4 узла на одном дворовом проезде,
    // маршруты по 400-530 м), — кольцо пошире.
    RoadGraphNode? fallback;
    for (final maxDistance in const [spawnMaxDistance, _wideSpawnMaxDistance]) {
      final ring = <RoadGraphNode>[];
      for (final node in graph.nodes.values) {
        if (adjacency[node.id]?.isEmpty ?? true) continue;
        final distance = (node.toVector3() - targetPosition).length;
        if (distance >= spawnMinDistance && distance <= maxDistance) ring.add(node);
      }
      if (ring.isEmpty) continue;
      final picked = _pickWithSaneRoute(ring, targetPosition);
      if (picked.sane) return picked.node;
      fallback ??= picked.node;
    }
    if (fallback != null) return fallback;

    final nearestId = nearestVehicleNodeId(graph, adjacency, targetPosition);
    return nearestId != null ? graph.nodes[nearestId] : null;
  }

  /// Из кандидатов кольца — тот, от которого до игрока можно доехать без
  /// огромной петли: на живой погоне кратчайший путь от части узлов кольца
  /// уводил машину на 200 м в объезд квартала, и до игрока она добиралась
  /// за минуту. Пробует до [_spawnCandidates] случайных узлов, берёт
  /// первый с маршрутом не длиннее [_maxRouteDetour] прямых расстояний,
  /// иначе — с самым коротким маршрутом.
  ({RoadGraphNode node, bool sane}) _pickWithSaneRoute(List<RoadGraphNode> ring, vm.Vector3 targetPosition) {
    final goalId = nearestVehicleNodeId(graph, adjacency, targetPosition);
    if (goalId == null) return (node: ring[_random.nextInt(ring.length)], sane: true);
    final candidates = [...ring]..shuffle(_random);
    RoadGraphNode? best;
    var bestRatio = double.infinity;
    for (final node in candidates.take(_spawnCandidates)) {
      final path = findShortestPath(graph, adjacency, node.id, goalId);
      if (path == null) continue;
      final ratio = routeLength(graph, path) / math.max(1.0, (node.toVector3() - targetPosition).length);
      if (ratio <= _maxRouteDetour) return (node: node, sane: true);
      if (ratio < bestRatio) {
        bestRatio = ratio;
        best = node;
      }
    }
    return (node: best ?? candidates.first, sane: false);
  }

  static const double _wideSpawnMaxDistance = 160.0;
  static const int _spawnCandidates = 12;
  static const double _maxRouteDetour = 2.5;
}
