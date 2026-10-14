import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../vehicles/vehicle.dart';
import '../vehicles/vehicle_spec.dart';
import '../world/road_graph.dart';
import 'police_car.dart';
import 'road_pathfinding.dart';
import 'wanted_state.dart';

/// Одна активная патрульная машина + её AI-состояние (текущий путь по
/// дорожному графу и таймер до перерасчёта). Путь хранит id узлов
/// ВПЕРЕДИ машины (текущий узел уже не включён — см. PoliceSystem._repath).
class _PoliceUnit {
  _PoliceUnit(this.vehicle);

  final BuiltVehicle vehicle;
  final List<String> path = [];
  double repathTimer = 0.0;
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
  PoliceSystem._({required this.graph, required this.scene, required VehicleSpec policeSpec, math.Random? random})
    : adjacency = buildVehicleAdjacency(graph),
      _policeSpec = policeSpec,
      _random = random ?? math.Random();

  /// Спека грузится один раз здесь (асинхронно, во время Game.load()) —
  /// сам спавн машины внутри update() синхронный (buildVehicleWithSpec, а
  /// не buildVehicle), потому что update() зовётся каждый кадр из
  /// Game.tick(), который не async.
  static Future<PoliceSystem> create({required RoadGraph graph, required Scene scene, math.Random? random}) async {
    final spec = await loadVehicleSpec('car_police_01') ?? _fallbackPoliceSpec;
    return PoliceSystem._(graph: graph, scene: scene, policeSpec: spec, random: random);
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

  /// Узлы живых патрульных машин — чтобы игрок пешком не проходил сквозь
  /// них: коллизионная область персонажа собирается из ближних чанков
  /// района, а машины в чанки не входят (см. CharacterCollisionField).
  Iterable<Node> get unitNodes => _units.map((unit) => unit.vehicle.node);

  /// Зовётся каждый кадр из Game.tick(). Возвращает true ровно в кадр,
  /// когда игрок только что оказался пойман (машина рядом [arrestHoldSeconds]
  /// подряд) — Game сбрасывает розыск/телепортирует игрока в ответ.
  bool update(double dt, vm.Vector3 targetPosition) {
    final desired = wantedState.stars == 0 ? 0 : math.min(wantedState.stars, maxUnits);
    _syncUnitCount(desired, targetPosition);

    var anyClose = false;
    for (final unit in _units) {
      final carPos = unit.vehicle.node.globalTransform.getTranslation();

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

      if ((carPos - targetPosition).length <= arrestRadius) anyClose = true;
    }

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
    _arrestTimer = 0.0;
  }

  void _syncUnitCount(int desired, vm.Vector3 targetPosition) {
    while (_units.length < desired) {
      final unit = _spawnUnit(targetPosition);
      if (unit == null) break; // негде заспавнить — не зацикливаемся
      _units.add(unit);
    }
    while (_units.length > desired) {
      final unit = _units.removeLast();
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
    return _PoliceUnit(vehicle);
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
        targetPosition: waypointPos,
      );
      unit.vehicle.controller.setInput(throttle: input.throttle, steer: input.steer);
      return;
    }

    // Путь закончился (доехали до последней путевой точки, но, возможно,
    // ещё не вплотную к игроку — цель двигалась, пока машина ехала) — рулим
    // напрямую на игрока до следующего пересчёта пути.
    final input = computePoliceInput(
      position: carPos,
      heading: unit.vehicle.controller.heading,
      targetPosition: targetPosition,
    );
    unit.vehicle.controller.setInput(throttle: input.throttle, steer: input.steer);
  }

  /// Узел дорожного графа в кольце [spawnMinDistance]..[spawnMaxDistance] от
  /// игрока — вне поля зрения, но не через полкарты. Если в кольце нет
  /// проезжих узлов (игрок у края района), берёт ближайший проезжий узел
  /// вообще — лучше заспавнить чуть ближе, чем не заспавнить совсем.
  RoadGraphNode? _pickSpawnNode(vm.Vector3 targetPosition) {
    final ring = <RoadGraphNode>[];
    for (final node in graph.nodes.values) {
      if (adjacency[node.id]?.isEmpty ?? true) continue;
      final distance = (node.toVector3() - targetPosition).length;
      if (distance >= spawnMinDistance && distance <= spawnMaxDistance) ring.add(node);
    }
    if (ring.isNotEmpty) return ring[_random.nextInt(ring.length)];

    final nearestId = nearestVehicleNodeId(graph, adjacency, targetPosition);
    return nearestId != null ? graph.nodes[nearestId] : null;
  }
}
