import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../vehicles/vehicle.dart';
import 'traffic_car.dart';

class _TrafficUnit {
  _TrafficUnit(this.car, this.node);

  final TrafficCar car;
  final Node node;
}

/// Фоновый трафик: [population] машин ездят по дорогам вокруг игрока (см.
/// traffic_car.dart — сама езда проверена юнит-тестами отдельно от рендера).
///
/// Существование — только по расстоянию до игрока, камера не участвует
/// (PROGRESS.md, "Принцип, который нельзя нарушать"): уехавшая дальше
/// [despawnRadius] машина переселяется в кольцо [respawnMinDistance]..
/// [respawnMaxDistance], а не возникает перед носом.
///
/// Каждая машина — свой узел с декоративным кузовом (buildStaticVehicleVisual),
/// без VehicleControllerComponent: лучи и физика не нужны, а машина игрока
/// врезается в эти кузова по-настоящему, потому что её лучи обходят сцену.
class TrafficSystem {
  TrafficSystem({
    required this.network,
    required this.scene,
    this.population = 8,
    this.initialMinDistance = 25.0,
    this.respawnMinDistance = 70.0,
    this.respawnMaxDistance = 150.0,
    this.despawnRadius = 220.0,
    math.Random? random,
  }) : _random = random ?? math.Random();

  final TrafficNetwork network;
  final Scene scene;
  final int population;
  final double initialMinDistance;
  final double respawnMinDistance;
  final double respawnMaxDistance;
  final double despawnRadius;
  final math.Random _random;

  final List<_TrafficUnit> _units = [];
  bool _spawned = false;

  /// Полуширина машины трафика как препятствия — для других систем.
  static const double obstacleRadius = 1.0;

  /// Застрявшую дольше этого машину переселяем — но только вдали от игрока
  /// (см. [_stuckRespawnDistance]), чтобы она не пропала у него на глазах.
  static const double _stuckSeconds = 20.0;
  static const double _stuckRespawnDistance = 60.0;

  /// Не ставить новую машину ближе этого к другой.
  static const double _spawnSpacing = 15.0;

  static final List<vm.Vector4> _paints = [
    vm.Vector4(0.12, 0.32, 0.62, 1.0), // синий
    vm.Vector4(0.75, 0.15, 0.12, 1.0), // красный
    vm.Vector4(0.85, 0.85, 0.82, 1.0), // белый
    vm.Vector4(0.08, 0.08, 0.09, 1.0), // чёрный
    vm.Vector4(0.55, 0.57, 0.6, 1.0), // серебристый
    vm.Vector4(0.2, 0.42, 0.25, 1.0), // зелёный
    vm.Vector4(0.82, 0.62, 0.15, 1.0), // жёлтое такси
  ];

  /// Узлы машин — чтобы пешком сквозь них не пройти (CharacterCollisionField).
  Iterable<Node> get carNodes => _units.map((unit) => unit.node);

  /// Машины трафика как препятствия для других (полиции, пешеходов).
  Iterable<TrafficObstacle> get obstacles =>
      _units.map((unit) => (position: unit.car.position, radius: obstacleRadius));

  /// Зовётся каждый кадр из Game.tick(). [external] — то, перед чем машины
  /// должны тормозить помимо друг друга: игрок, его машина, полиция,
  /// пешеходы.
  void update(double dt, vm.Vector3 trackedPosition, {Iterable<TrafficObstacle> external = const []}) {
    if (!_spawned) {
      _spawned = true;
      for (var i = 0; i < population; i++) {
        final car = _spawnCar(trackedPosition, initialMinDistance, respawnMaxDistance);
        if (car == null) break;
        final node = _buildCarNode();
        scene.add(node);
        final unit = _TrafficUnit(car, node);
        _units.add(unit);
        _syncNode(unit);
      }
    }

    final externalList = external.toList();
    final cars = [for (final unit in _units) unit.car];
    final despawnSq = despawnRadius * despawnRadius;
    for (final unit in _units) {
      final canDrive = stepTrafficCar(
        unit.car,
        network,
        dt: dt,
        random: _random,
        obstacles: externalList,
        traffic: cars,
      );

      final distanceSq = (unit.car.position - trackedPosition).length2;
      final stuckFarAway = (!canDrive || unit.car.stoppedSeconds > _stuckSeconds) &&
          distanceSq > _stuckRespawnDistance * _stuckRespawnDistance;
      if (distanceSq > despawnSq || stuckFarAway) {
        final fresh = _spawnCar(trackedPosition, respawnMinDistance, respawnMaxDistance);
        if (fresh != null) _replaceCar(unit, fresh);
      }
      _syncNode(unit);
    }
  }

  void _replaceCar(_TrafficUnit unit, TrafficCar fresh) {
    unit.car
      ..position = fresh.position
      ..heading = fresh.heading
      ..speed = 0.0
      ..fromNodeId = fresh.fromNodeId
      ..toNodeId = fresh.toNodeId
      ..nextNodeId = null
      ..stoppedSeconds = 0.0
      ..isTurningAround = false;
  }

  void _syncNode(_TrafficUnit unit) {
    unit.node
      ..position = unit.car.position
      ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), unit.car.heading);
  }

  Node _buildCarNode() {
    final archetypes = [VehicleArchetype.sedan, VehicleArchetype.hatchback, VehicleArchetype.pickup];
    final base = archetypes[_random.nextInt(archetypes.length)];
    return buildStaticVehicleVisual(base.withPaint(_paints[_random.nextInt(_paints.length)]));
  }

  /// Машина в начале случайного ребра трафика, начало которого в кольце
  /// [minDistance]..[maxDistance] от игрока и не ближе [_spawnSpacing] к
  /// другим машинам. null — подходящих мест нет.
  TrafficCar? _spawnCar(vm.Vector3 center, double minDistance, double maxDistance) {
    final candidates = <String>[];
    for (final entry in network.adjacency.entries) {
      final node = network.graph.nodes[entry.key];
      if (node == null || entry.value.isEmpty) continue;
      final distance = (node.toVector3() - center).length;
      if (distance >= minDistance && distance <= maxDistance) candidates.add(entry.key);
    }
    for (var attempt = 0; attempt < 12 && candidates.isNotEmpty; attempt++) {
      final fromId = candidates[_random.nextInt(candidates.length)];
      final exits = network.adjacency[fromId]!;
      final toId = exits[_random.nextInt(exits.length)];
      final from = network.graph.nodes[fromId]!.toVector3();
      final to = network.graph.nodes[toId]!.toVector3();
      final direction = to - from;
      if (direction.length2 < 1e-6) continue;
      direction.normalize();
      final isOneway = network.edge(fromId, toId)?.oneway ?? false;
      final position = from + (isOneway ? vm.Vector3.zero() : rightOf(direction) * trafficLaneOffset);
      final crowded = _units.any(
        (unit) => (unit.car.position - position).length2 < _spawnSpacing * _spawnSpacing,
      );
      if (crowded) continue;
      return TrafficCar(
        position: position,
        heading: math.atan2(direction.x, direction.z),
        fromNodeId: fromId,
        toNodeId: toId,
        priority: _random.nextInt(1 << 30),
      );
    }
    return null;
  }
}
