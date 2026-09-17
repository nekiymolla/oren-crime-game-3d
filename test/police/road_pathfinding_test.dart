import 'package:crime_oren/police/road_pathfinding.dart';
import 'package:crime_oren/world/road_graph.dart';
import 'package:flutter_test/flutter_test.dart';

RoadGraph _buildLineGraph() {
  // a -- b -- c -- d, все residential, двусторонние.
  return const RoadGraph(
    nodes: {
      'a': RoadGraphNode(id: 'a', x: 0, z: 0),
      'b': RoadGraphNode(id: 'b', x: 10, z: 0),
      'c': RoadGraphNode(id: 'c', x: 20, z: 0),
      'd': RoadGraphNode(id: 'd', x: 30, z: 0),
    },
    edges: [
      RoadGraphEdge(from: 'a', to: 'b', highway: 'residential', oneway: false),
      RoadGraphEdge(from: 'b', to: 'c', highway: 'residential', oneway: false),
      RoadGraphEdge(from: 'c', to: 'd', highway: 'residential', oneway: false),
    ],
  );
}

void main() {
  test('buildVehicleAdjacency игнорирует пешеходные типы дорог', () {
    final graph = RoadGraph(
      nodes: const {
        'a': RoadGraphNode(id: 'a', x: 0, z: 0),
        'b': RoadGraphNode(id: 'b', x: 10, z: 0),
      },
      edges: const [
        RoadGraphEdge(from: 'a', to: 'b', highway: 'footway', oneway: false),
      ],
    );
    final adjacency = buildVehicleAdjacency(graph);
    expect(adjacency['a'] ?? const [], isEmpty);
  });

  test('buildVehicleAdjacency уважает oneway — обратного ребра нет', () {
    final graph = RoadGraph(
      nodes: const {
        'a': RoadGraphNode(id: 'a', x: 0, z: 0),
        'b': RoadGraphNode(id: 'b', x: 10, z: 0),
      },
      edges: const [
        RoadGraphEdge(from: 'a', to: 'b', highway: 'residential', oneway: true),
      ],
    );
    final adjacency = buildVehicleAdjacency(graph);
    expect(adjacency['a'], ['b']);
    expect(adjacency['b'] ?? const [], isEmpty);
  });

  test('findShortestPath находит путь через промежуточные узлы', () {
    final graph = _buildLineGraph();
    final adjacency = buildVehicleAdjacency(graph);
    final path = findShortestPath(graph, adjacency, 'a', 'd');
    expect(path, ['a', 'b', 'c', 'd']);
  });

  test('findShortestPath возвращает null, если узлы не связаны', () {
    final graph = RoadGraph(
      nodes: const {
        'a': RoadGraphNode(id: 'a', x: 0, z: 0),
        'b': RoadGraphNode(id: 'b', x: 10, z: 0),
      },
      edges: const [],
    );
    final adjacency = buildVehicleAdjacency(graph);
    expect(findShortestPath(graph, adjacency, 'a', 'b'), isNull);
  });

  test('nearestVehicleNodeId игнорирует узлы без проезжих соседей', () {
    final graph = RoadGraph(
      nodes: const {
        'isolated': RoadGraphNode(id: 'isolated', x: 0, z: 0),
        'a': RoadGraphNode(id: 'a', x: 100, z: 0),
        'b': RoadGraphNode(id: 'b', x: 110, z: 0),
      },
      edges: const [
        RoadGraphEdge(from: 'a', to: 'b', highway: 'residential', oneway: false),
      ],
    );
    final adjacency = buildVehicleAdjacency(graph);
    final nearest = nearestVehicleNodeId(graph, adjacency, graph.nodes['isolated']!.toVector3());
    expect(nearest, 'a'); // ближе isolated, но у него нет проезжих соседей
  });
}
