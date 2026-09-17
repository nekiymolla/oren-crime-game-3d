import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../world/road_graph.dart';
import 'pedestrian.dart';

/// Держит NPC-пешеходов вокруг игрока/машины: спавнит рядом
/// ([spawnRadius]), телепортирует обратно рядом, когда отходят дальше
/// [despawnRadius], двигает по дорожному графу (см. pedestrian.dart —
/// сама ходьба протестирована юнит-тестом отдельно от рендера).
///
/// Рендер — один общий `InstancedMesh` на всех пешеходов (капсулы, как у
/// игрока, только меньше и разного цвета) — один draw call независимо от
/// [population]. НЕ используется built-in `ThirdPersonControllerComponent`
/// с его ground-рейкастами: у дорожного графа уже есть точная высота узлов
/// (все ~0, ровная земля), рейкастить незачем — а с N пешеходов это было
/// бы N лишних raycastNode на кадр, ровно та проблема с лагами, что
/// разбирали на Android этим утром (см. PROGRESS.md).
class PedestrianSystem {
  PedestrianSystem({
    required this.graph,
    required this.raycastRoot,
    this.population = 16,
    this.spawnRadius = 120.0,
    this.despawnRadius = 180.0,
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
  final double walkSpeed;
  final InstancedMesh bodies;

  final math.Random _random;
  final List<Pedestrian> _pedestrians = [];
  bool _spawned = false;

  /// Пешеход раньше шёл по прямой между узлами графа без проверки на
  /// препятствия — иногда это резало угол здания (см. PROGRESS.md).
  /// Проверяем каждое ребро рейкастом РОВНО ОДИН РАЗ (кэш по обеим
  /// сторонам) — не каждый кадр, поэтому не создаёт ту же проблему с
  /// лагами, что N живых ground-рейкастов на кадр (см. doc-комментарий
  /// класса): суммарная стоимость на весь граф ограничена числом рёбер
  /// (≤805 на весь район), а не числом пешеходов или кадров.
  final Map<String, bool> _edgePassable = {};

  static const double _eyeHeight = 1.0;

  /// Ниже которой наезд машиной не считается — стоящая/едва катящаяся
  /// машина у пешехода не в счёт, только реальный удар.
  static const double hitSpeedThreshold = 3.0;
  static const double _hitRadius = 1.0;

  Node buildNode() => Node()..addComponent(InstancedMeshComponent(bodies));

  /// Зовётся каждый кадр из Game.tick(). Первый вызов лениво спавнит
  /// начальную популяцию вокруг [trackedPosition] — раньше нельзя, узлы
  /// графа сами по себе не знают, где стартует игрок. [vehiclePosition]/
  /// [vehicleSpeed] — если заданы (машина существует и её скорость выше
  /// [hitSpeedThreshold]), пешеходы в радиусе удара телепортируются
  /// (см. _respawnNear) и засчитываются в возвращаемое число наездов —
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

      if (canHit && (pedestrian.position - vehiclePosition).length2 <= hitRadiusSq) {
        hits++;
        _respawnNear(pedestrian, trackedPosition);
      } else if ((pedestrian.position - trackedPosition).length2 > despawnRadiusSq) {
        _respawnNear(pedestrian, trackedPosition);
      }

      bodies.setInstanceTransform(
        pedestrian.instanceIndex,
        vm.Matrix4.compose(
          pedestrian.position + vm.Vector3(0, _totalHeight / 2, 0),
          vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), pedestrian.yaw),
          vm.Vector3.all(1.0),
        ),
      );
    }
    return hits;
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

  void _respawnNear(Pedestrian pedestrian, vm.Vector3 center) {
    final fresh = _createAt(_randomWalkableNodeNear(center));
    pedestrian
      ..position = fresh.position
      ..currentNodeId = fresh.currentNodeId
      ..targetNodeId = fresh.targetNodeId;
  }

  Pedestrian _createAt(RoadGraphNode node) {
    final neighbors = adjacency[node.id] ?? const <String>[];
    final target = neighbors.isNotEmpty ? neighbors[_random.nextInt(neighbors.length)] : node.id;
    final pedestrian = Pedestrian(position: node.toVector3(), currentNodeId: node.id, targetNodeId: target);
    _ensurePassableTarget(pedestrian);
    return pedestrian;
  }

  /// Если текущая цель пешехода режет угол здания (см. doc-комментарий
  /// [_edgePassable]), перебирает соседей узла в поисках проходимого —
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
    final cached = _edgePassable[key];
    if (cached != null) return cached;

    final from = graph.nodes[fromId];
    final to = graph.nodes[toId];
    bool passable;
    if (from == null || to == null || fromId == toId) {
      passable = true;
    } else {
      final origin = from.toVector3(y: _eyeHeight);
      final delta = to.toVector3(y: _eyeHeight) - origin;
      final distance = delta.length;
      // Чуть недолетаем до цели: сама конечная точка иногда лежит впритык
      // к стене (узел на углу дома), не должна давать ложный "перекрыто".
      passable = distance < 0.5 ||
          raycastNode(raycastRoot, vm.Ray.originDirection(origin, delta), maxDistance: distance - 0.5) ==
              null;
    }
    _edgePassable[key] = passable;
    return passable;
  }

  /// Только узлы с хотя бы одним соседом — иначе пешеход появится и сразу
  /// встанет колом (см. advancePedestrian: без соседей цель = сам узел).
  RoadGraphNode _randomWalkableNodeNear(vm.Vector3 center) {
    final nearby = <RoadGraphNode>[];
    final radiusSq = spawnRadius * spawnRadius;
    for (final node in graph.nodes.values) {
      if (adjacency[node.id]?.isEmpty ?? true) continue;
      if ((node.toVector3() - center).length2 <= radiusSq) nearby.add(node);
    }
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
