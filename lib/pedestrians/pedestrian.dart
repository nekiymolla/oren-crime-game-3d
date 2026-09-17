import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import '../world/road_graph.dart';

/// Чистое (без Flutter/flutter_scene) состояние одного NPC-пешехода —
/// отдельно от рендера (см. pedestrian_system.dart), чтобы саму логику
/// ходьбы можно было проверить юнит-тестом без GPU (создание геометрии
/// требует живого Impeller-контекста, см. PROGRESS.md).
///
/// Пешеход всегда идёт к [targetNodeId] по прямой (дороги в дорожном графе
/// и так соединяют соседние точки короткими сегментами, полноценный A*
/// не нужен) и на прибытии выбирает случайного соседа текущего узла —
/// вместо того, откуда пришёл, если есть выбор.
class Pedestrian {
  Pedestrian({
    required this.position,
    required this.currentNodeId,
    required this.targetNodeId,
    this.yaw = 0.0,
  });

  vm.Vector3 position;
  String currentNodeId;
  String targetNodeId;
  double yaw;

  /// Индекс инстанса в общем InstancedMesh (см. PedestrianSystem) — не
  /// логика, просто чтобы рендеру было куда писать обновлённый transform.
  int instanceIndex = -1;
}

const double _arrivalEpsilon = 0.1;

/// Строит карту соседей по рёбрам графа — двунаправленно (пешеход идёт по
/// тротуару в любую сторону независимо от oneway для машин).
Map<String, List<String>> buildPedestrianAdjacency(RoadGraph graph) {
  final adjacency = <String, List<String>>{};
  for (final edge in graph.edges) {
    (adjacency[edge.from] ??= []).add(edge.to);
    (adjacency[edge.to] ??= []).add(edge.from);
  }
  return adjacency;
}

/// Двигает [pedestrian] на [speed]*[dt] метров к его текущей цели; по
/// прибытии выбирает новую цель среди соседей [adjacency] и возвращает
/// true (полезно для тестов и для эффектов вроде "пешеход дошёл").
/// Пешеходов с узлом без соседей быть не должно (см. spawn-логику в
/// PedestrianSystem) — если так всё же случилось, просто стоит на месте.
bool advancePedestrian(
  Pedestrian pedestrian,
  RoadGraph graph,
  Map<String, List<String>> adjacency, {
  required double dt,
  required double speed,
  required math.Random random,
}) {
  final target = graph.nodes[pedestrian.targetNodeId];
  if (target == null) return false;

  final targetPos = target.toVector3();
  final toTarget = targetPos - pedestrian.position;
  final distance = toTarget.length;

  if (distance <= _arrivalEpsilon) {
    pedestrian.position = targetPos;
    final arrivedNodeId = pedestrian.targetNodeId;
    final neighbors = adjacency[arrivedNodeId];
    if (neighbors == null || neighbors.isEmpty) return true;

    final candidates = neighbors.where((id) => id != pedestrian.currentNodeId).toList();
    final pool = candidates.isNotEmpty ? candidates : neighbors;
    pedestrian.currentNodeId = arrivedNodeId;
    pedestrian.targetNodeId = pool[random.nextInt(pool.length)];
    return true;
  }

  final direction = toTarget / distance;
  final step = math.min(speed * dt, distance);
  pedestrian.position += direction * step;
  pedestrian.yaw = math.atan2(direction.x, direction.z);
  return false;
}
