import 'package:crime_oren/world/road_graph.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RoadGraph.fromJson разбирает узлы и рёбра', () {
    final graph = RoadGraph.fromJson({
      'nodes': [
        {'id': 'a', 'x': 1.5, 'z': -2.0},
        {'id': 'b', 'x': 4.0, 'z': 0.0},
      ],
      'edges': [
        {'from': 'a', 'to': 'b', 'highway': 'residential', 'oneway': false},
      ],
    });

    expect(graph.nodes, hasLength(2));
    expect(graph.nodes['a']!.x, 1.5);
    expect(graph.nodes['a']!.z, -2.0);
    expect(graph.edges, hasLength(1));
    expect(graph.edges.single.highway, 'residential');
    expect(graph.edges.single.oneway, isFalse);
  });

  test('RoadGraphNode.toVector3 подставляет X/Z на нужную высоту', () {
    const node = RoadGraphNode(id: 'a', x: 3.0, z: -7.0);
    final v = node.toVector3(y: 1.2);
    expect(v.x, closeTo(3.0, 1e-6));
    expect(v.y, closeTo(1.2, 1e-6));
    expect(v.z, closeTo(-7.0, 1e-6));
  });
}
