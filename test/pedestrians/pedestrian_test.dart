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
  knockdownTests();

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

void _advance(Pedestrian pedestrian, RoadGraph graph, double seconds) {
  final adjacency = buildPedestrianAdjacency(graph);
  final random = Random(1);
  for (var i = 0; i < (seconds * 60).round(); i++) {
    advancePedestrian(pedestrian, graph, adjacency, dt: 1 / 60, speed: 1.3, random: random);
  }
}

void knockdownTests() {
  test('сбитый пешеход отлетает от машины и лежит, не идя к цели', () {
    final graph = _lineGraph();
    final pedestrian = Pedestrian(position: vm.Vector3(5, 0, 0), currentNodeId: 'a', targetNodeId: 'b');
    // Машина сбоку (с -Z) на скорости 15 м/с.
    pedestrian.knockDown(vm.Vector3(5, 0, -1), 15.0, lieSeconds: 3.0);
    _advance(pedestrian, graph, 2.0);
    expect(pedestrian.isKnockedDown, isTrue);
    expect(pedestrian.position.z, greaterThan(0.5)); // отлетел от машины
    expect(pedestrian.position.x, closeTo(5, 1e-6)); // к цели не шёл
  });

  test('встав, сначала возвращается на ребро, потом идёт к цели', () {
    final graph = _lineGraph();
    final pedestrian = Pedestrian(position: vm.Vector3(5, 0, 0), currentNodeId: 'a', targetNodeId: 'b');
    pedestrian.knockDown(vm.Vector3(5, 0, -1), 15.0, lieSeconds: 1.0);
    _advance(pedestrian, graph, 1.0);
    final landedZ = pedestrian.position.z;
    expect(landedZ, greaterThan(0.5));

    // Возврат на ребро идёт строго обратно, по x не смещаясь.
    _advance(pedestrian, graph, 0.3);
    expect(pedestrian.position.z, lessThan(landedZ));
    expect(pedestrian.position.x, closeTo(5, 1e-6));

    _advance(pedestrian, graph, 3.0);
    expect(pedestrian.returnPoint, isNull);
    expect(pedestrian.position.z, closeTo(0, 1e-6));
    expect(pedestrian.position.x, greaterThan(5.5)); // пошёл дальше к b
  });

  test('повторный удар лежачего не сбрасывает точку возврата на ребро', () {
    final pedestrian = Pedestrian(position: vm.Vector3(5, 0, 0), currentNodeId: 'a', targetNodeId: 'b');
    pedestrian.knockDown(vm.Vector3(5, 0, -1), 15.0);
    pedestrian.position = vm.Vector3(5, 0, 2);
    pedestrian.knockDown(vm.Vector3(5, 0, 1), 15.0);
    expect(pedestrian.returnPoint!.z, closeTo(0, 1e-6));
  });
}
