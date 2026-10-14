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

  /// Сколько ещё секунд лежит сбитый машиной (0 — на ногах).
  double knockedDownSeconds = 0.0;

  /// Скорость отлёта после удара, гасится трением (см. [advancePedestrian]).
  vm.Vector3 knockbackVelocity = vm.Vector3.zero();

  /// Точка на ребре графа, где пешехода сбили: встав, он сперва
  /// возвращается сюда, а уже потом идёт к цели. Иначе он пошёл бы к цели
  /// по прямой из места падения — в стороне от ребра, а гарантия "сквозь
  /// дома не ходит" держится именно на том, что пешеход идёт по рёбрам
  /// (см. tools/osm_pipeline/check_road_graph.mjs).
  vm.Vector3? returnPoint;

  bool get isKnockedDown => knockedDownSeconds > 0.0;

  /// Удар машиной: отлетает от [impactFrom] (центр машины) со скоростью,
  /// растущей со скоростью машины [impactSpeed], и лежит [lieSeconds].
  void knockDown(
    vm.Vector3 impactFrom,
    double impactSpeed, {
    double lieSeconds = 6.0,
  }) {
    returnPoint ??= position.clone();
    knockedDownSeconds = lieSeconds;
    final away = vm.Vector3(position.x - impactFrom.x, 0, position.z - impactFrom.z);
    if (away.length2 < 1e-6) away.setValues(math.sin(yaw), 0, math.cos(yaw));
    away.normalize();
    knockbackVelocity = away * math.min(impactSpeed * 0.4, 6.0);
    yaw = math.atan2(away.x, away.z);
  }
}

/// Трение скольжения сбитого пешехода по земле, 1/с: при отлёте 6 м/с
/// он проезжает около метра (6 / 6).
const double _knockbackFriction = 6.0;

const double _arrivalEpsilon = 0.1;

/// Типы `highway`, по которым реально ходят пешком — не тротуары/полосы
/// именно для машин (`tertiary` и подобные) или для великов (`cycleway`).
/// Без фильтра пешеходы гуляли прямо по проезжей части (замечено
/// пользователем) — в наших OSM-данных отдельных тротуаров почти нет,
/// `residential`/`unclassified`/`service` — обычные дворовые/жилые улицы
/// без явного разделения на полосы, пешком по ним ходить реалистично.
const Set<String> pedestrianHighwayTypes = {
  'footway',
  'path',
  'pedestrian',
  'living_street',
  'residential',
  'unclassified',
  'service',
  'steps',
};

/// Строит карту соседей по рёбрам графа — двунаправленно (пешеход идёт по
/// тротуару в любую сторону независимо от oneway для машин), только по
/// [pedestrianHighwayTypes].
Map<String, List<String>> buildPedestrianAdjacency(RoadGraph graph) {
  final adjacency = <String, List<String>>{};
  for (final edge in graph.edges) {
    if (!pedestrianHighwayTypes.contains(edge.highway)) continue;
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
  if (pedestrian.isKnockedDown) {
    pedestrian.knockedDownSeconds = math.max(0.0, pedestrian.knockedDownSeconds - dt);
    pedestrian.position += pedestrian.knockbackVelocity * dt;
    pedestrian.knockbackVelocity.scale(math.exp(-_knockbackFriction * dt));
    return false;
  }

  // Встал после удара — сначала обратно на ребро (см. Pedestrian.returnPoint).
  final returnPoint = pedestrian.returnPoint;
  if (returnPoint != null) {
    final back = returnPoint - pedestrian.position;
    final backDistance = back.length;
    if (backDistance <= _arrivalEpsilon) {
      pedestrian.position = returnPoint;
      pedestrian.returnPoint = null;
    } else {
      final direction = back / backDistance;
      pedestrian.position += direction * math.min(speed * dt, backDistance);
      pedestrian.yaw = math.atan2(direction.x, direction.z);
      return false;
    }
  }

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
