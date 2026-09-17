import 'dart:math';

import 'package:crime_oren/pedestrians/pedestrian.dart';
import 'package:crime_oren/world/road_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

RoadGraph _lineGraph() {
  // a --- b --- c  (a и c — тупики, b — развилка на две стороны)
  return RoadGraph(
    nodes: {
      'a': const RoadGraphNode(id: 'a', x: 0, z: 0),
      'b': const RoadGraphNode(id: 'b', x: 10, z: 0),
      'c': const RoadGraphNode(id: 'c', x: 20, z: 0),
    },
    edges: const [
      RoadGraphEdge(from: 'a', to: 'b', highway: 'residential', oneway: false),
      RoadGraphEdge(from: 'b', to: 'c', highway: 'residential', oneway: false),
    ],
  );
}

void main() {
  test('buildPedestrianAdjacency строит связи в обе стороны', () {
    final adjacency = buildPedestrianAdjacency(_lineGraph());
    expect(adjacency['a'], ['b']);
    expect(adjacency['b'], containsAll(['a', 'c']));
    expect(adjacency['c'], ['b']);
  });

  test('advancePedestrian двигает к цели пропорционально speed*dt, не долетая', () {
    final graph = _lineGraph();
    final adjacency = buildPedestrianAdjacency(graph);
    final pedestrian = Pedestrian(position: vm.Vector3(0, 0, 0), currentNodeId: 'a', targetNodeId: 'b');

    final arrived = advancePedestrian(
      pedestrian,
      graph,
      adjacency,
      dt: 1.0,
      speed: 2.0,
      random: Random(0),
    );

    expect(arrived, isFalse);
    expect(pedestrian.position.x, closeTo(2.0, 1e-6));
    expect(pedestrian.targetNodeId, 'b'); // цель не сменилась, ещё в пути
  });

  test('advancePedestrian долетает и выбирает нового соседа, не возвращаясь назад', () {
    final graph = _lineGraph();
    final adjacency = buildPedestrianAdjacency(graph);
    // Уже почти у 'b' (10,0) — один шаг долетает и переключает цель.
    final pedestrian = Pedestrian(
      position: vm.Vector3(9.95, 0, 0),
      currentNodeId: 'a',
      targetNodeId: 'b',
    );

    final arrived = advancePedestrian(
      pedestrian,
      graph,
      adjacency,
      dt: 1.0,
      speed: 5.0,
      random: Random(0),
    );

    expect(arrived, isTrue);
    expect(pedestrian.currentNodeId, 'b');
    // У 'b' два соседа (a, c) — раз пришли из 'a', новая цель должна быть 'c'.
    expect(pedestrian.targetNodeId, 'c');
  });

  test('advancePedestrian на тупике идёт назад — единственный сосед', () {
    final graph = _lineGraph();
    final adjacency = buildPedestrianAdjacency(graph);
    // У узла 'a' единственный сосед — 'b', ровно тот, откуда пришли.
    final pedestrian = Pedestrian(
      position: vm.Vector3(0.02, 0, 0),
      currentNodeId: 'b',
      targetNodeId: 'a',
    );

    advancePedestrian(pedestrian, graph, adjacency, dt: 1.0, speed: 5.0, random: Random(0));

    expect(pedestrian.currentNodeId, 'a');
    expect(pedestrian.targetNodeId, 'b');
  });
}
