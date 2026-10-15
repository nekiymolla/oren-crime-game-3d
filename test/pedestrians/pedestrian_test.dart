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
  panicTests();
  shootingTests();

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

void panicTests() {
  test('перепуганный водитель бежит быстрее шага, потом успокаивается', () {
    final graph = _lineGraph();
    final pedestrian = Pedestrian(position: vm.Vector3(0, 0, 0), currentNodeId: 'a', targetNodeId: 'b')
      ..panicSeconds = 1.0;
    _advance(pedestrian, graph, 1.0);
    expect(pedestrian.position.x, closeTo(1.3 * panicSpeedMultiplier, 0.05));
    expect(pedestrian.panicSeconds, 0.0);
    final before = pedestrian.position.x;
    _advance(pedestrian, graph, 1.0);
    expect(pedestrian.position.x - before, closeTo(1.3, 0.05));
  });
}

void shootingTests() {
  test('три пули пистолета в корпус убивают, мёртвый не ходит', () {
    final graph = _lineGraph();
    final adjacency = buildPedestrianAdjacency(graph);
    final pedestrian = Pedestrian(position: vm.Vector3(5, 0, 0), currentNodeId: 'a', targetNodeId: 'b');
    final shooter = vm.Vector3(5, 0, -10);
    expect(pedestrian.takeDamage(34, shooter), isFalse);
    expect(pedestrian.panicSeconds, greaterThan(0));
    expect(pedestrian.takeDamage(34, shooter), isFalse);
    expect(pedestrian.takeDamage(34, shooter), isTrue);
    expect(pedestrian.isDead, isTrue);
    expect(pedestrian.isShootable, isFalse);
    expect(pedestrian.takeDamage(34, shooter), isFalse); // второй раз не умирает

    final before = pedestrian.position.clone();
    advancePedestrian(pedestrian, graph, adjacency, dt: 1.0, speed: 2.0, random: Random(0));
    expect(pedestrian.position, before);
    expect(pedestrian.deadSeconds, 1.0);

    pedestrian.revive();
    expect(pedestrian.isDead, isFalse);
    expect(pedestrian.health, Pedestrian.maxHealth);
  });

  test('испуганный выстрелом разворачивается и бежит прочь от стрелка', () {
    final graph = _lineGraph();
    final adjacency = buildPedestrianAdjacency(graph);
    // Идёт от a к b, а стреляют со стороны b — разворачивается к a.
    final pedestrian = Pedestrian(position: vm.Vector3(5, 0, 0), currentNodeId: 'a', targetNodeId: 'b');
    pedestrian.scare(vm.Vector3(15, 0, 0), graph);
    expect(pedestrian.targetNodeId, 'a');
    expect(pedestrian.panicSeconds, greaterThan(0));
    advancePedestrian(pedestrian, graph, adjacency, dt: 0.5, speed: 1.3, random: Random(0));
    expect(pedestrian.position.x, lessThan(5));
  });

  test('в панике на развилке выбирает соседа подальше от стрелка', () {
    final graph = _lineGraph();
    final adjacency = buildPedestrianAdjacency(graph);
    // Бежит к развилке b со стороны a, стрелок у a — дальше бежать к c.
    final pedestrian = Pedestrian(position: vm.Vector3(9.95, 0, 0), currentNodeId: 'a', targetNodeId: 'b');
    pedestrian.scare(vm.Vector3(-5, 0, 0), graph);
    for (var i = 0; i < 20; i++) {
      advancePedestrian(pedestrian, graph, adjacency, dt: 0.05, speed: 1.3, random: Random(i));
    }
    expect(pedestrian.targetNodeId, 'c');
  });
}
