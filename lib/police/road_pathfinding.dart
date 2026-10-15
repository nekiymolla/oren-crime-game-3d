import 'package:vector_math/vector_math.dart' as vm;

import '../world/road_graph.dart';

/// Типы `highway`, по которым реально может ехать машина — не тротуары для
/// пешеходов ([footway]/[path]/[pedestrian]/[steps]) и не полосы для
/// великов ([cycleway]). Полицейские машины (см. police_system.dart) ищут
/// путь только по этому подграфу.
const Set<String> vehicleHighwayTypes = {
  'residential',
  'unclassified',
  'service',
  'tertiary',
  'secondary',
  'primary',
  'living_street',
};

/// Карта соседей для машин — в отличие от пешеходной (см. pedestrian.dart),
/// уважает [RoadGraphEdge.oneway]: по одностороннему ребру можно ехать
/// только from -> to.
Map<String, List<String>> buildVehicleAdjacency(RoadGraph graph) {
  final adjacency = <String, List<String>>{};
  for (final edge in graph.edges) {
    if (!vehicleHighwayTypes.contains(edge.highway)) continue;
    (adjacency[edge.from] ??= []).add(edge.to);
    if (!edge.oneway) (adjacency[edge.to] ??= []).add(edge.from);
  }
  return adjacency;
}

/// Ближайший к [position] узел графа среди тех, у кого в [adjacency] есть
/// хотя бы один сосед (изолированные узлы — тупиковые обрывки графа,
/// ехать туда/оттуда некуда). `null`, если таких узлов вообще нет.
String? nearestVehicleNodeId(RoadGraph graph, Map<String, List<String>> adjacency, vm.Vector3 position) {
  String? bestId;
  var bestDistanceSq = double.infinity;
  for (final node in graph.nodes.values) {
    if (adjacency[node.id]?.isEmpty ?? true) continue;
    final distanceSq = (node.toVector3() - position).length2;
    if (distanceSq < bestDistanceSq) {
      bestDistanceSq = distanceSq;
      bestId = node.id;
    }
  }
  return bestId;
}

/// Дейкстра по [adjacency] с весом ребра = евклидово расстояние между
/// узлами. Граф района небольшой (~700 узлов, см. PROGRESS.md), поэтому
/// простой O(V^2) перебор без кучи — не узкое место даже на слабом
/// Android, а вызывается редко (см. PoliceSystem._repathInterval), не
/// каждый кадр.
///
/// Возвращает список id узлов от [startId] (включительно) до [goalId]
/// (включительно), либо `null`, если пути нет.
List<String>? findShortestPath(
  RoadGraph graph,
  Map<String, List<String>> adjacency,
  String startId,
  String goalId,
) {
  if (startId == goalId) return [startId];

  final dist = <String, double>{startId: 0.0};
  final prev = <String, String>{};
  final visited = <String>{};

  while (true) {
    String? current;
    var best = double.infinity;
    for (final entry in dist.entries) {
      if (visited.contains(entry.key)) continue;
      if (entry.value < best) {
        best = entry.value;
        current = entry.key;
      }
    }
    if (current == null) return null;
    if (current == goalId) break;
    visited.add(current);

    final currentNode = graph.nodes[current];
    if (currentNode == null) continue;
    final currentPos = currentNode.toVector3();

    for (final neighborId in adjacency[current] ?? const <String>[]) {
      if (visited.contains(neighborId)) continue;
      final neighborNode = graph.nodes[neighborId];
      if (neighborNode == null) continue;
      final edgeLength = (neighborNode.toVector3() - currentPos).length;
      final candidate = dist[current]! + edgeLength;
      if (candidate < (dist[neighborId] ?? double.infinity)) {
        dist[neighborId] = candidate;
        prev[neighborId] = current;
      }
    }
  }

  final path = <String>[goalId];
  var node = goalId;
  while (node != startId) {
    final previous = prev[node];
    if (previous == null) return null;
    path.add(previous);
    node = previous;
  }
  return path.reversed.toList();
}

/// Длина маршрута [path] (id узлов) по прямым между узлами, метры.
double routeLength(RoadGraph graph, List<String> path) {
  var total = 0.0;
  for (var i = 1; i < path.length; i++) {
    final a = graph.nodes[path[i - 1]];
    final b = graph.nodes[path[i]];
    if (a == null || b == null) continue;
    total += (b.toVector3() - a.toVector3()).length;
  }
  return total;
}
