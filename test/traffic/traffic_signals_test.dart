import 'dart:math' as math;

import 'package:crime_oren/traffic/traffic_car.dart';
import 'package:crime_oren/traffic/traffic_signals.dart';
import 'package:crime_oren/world/road_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Крест: крупная дорога север-юг (tertiary) через узел c, дворовая
/// запад-восток (residential).
RoadGraph _cross() {
  final nodes = {
    'n': const RoadGraphNode(id: 'n', x: 0, z: -150),
    's': const RoadGraphNode(id: 's', x: 0, z: 150),
    'w': const RoadGraphNode(id: 'w', x: -150, z: 0),
    'e': const RoadGraphNode(id: 'e', x: 150, z: 0),
    'c': const RoadGraphNode(id: 'c', x: 0, z: 0),
  };
  return RoadGraph(
    nodes: nodes,
    edges: const [
      RoadGraphEdge(from: 'n', to: 'c', highway: 'tertiary', oneway: false),
      RoadGraphEdge(from: 'c', to: 's', highway: 'tertiary', oneway: false),
      RoadGraphEdge(from: 'w', to: 'c', highway: 'residential', oneway: false),
      RoadGraphEdge(from: 'c', to: 'e', highway: 'residential', oneway: false),
    ],
  );
}

void main() {
  test('цикл: группа вдоль оси — зелёный, жёлтый, красный; поперёк — наоборот', () {
    final intersection = SignalizedIntersection(
      nodeIds: {'c'},
      center: vm.Vector3.zero(),
      referenceAxis: vm.Vector3(0, 0, 1),
      offsetSeconds: 0,
    );
    final along = vm.Vector3(0, 0, -1); // против оси — та же группа
    final across = vm.Vector3(1, 0, 0);
    expect(intersection.lightFor(along, 1), SignalLight.green);
    expect(intersection.lightFor(across, 1), SignalLight.red);
    expect(intersection.lightFor(along, SignalTiming.green + 1), SignalLight.yellow);
    expect(intersection.lightFor(along, SignalTiming.green + SignalTiming.yellow + 1), SignalLight.red);
    expect(intersection.lightFor(across, SignalTiming.phase + 1), SignalLight.green);
    expect(intersection.lightFor(along, SignalTiming.phase + 1), SignalLight.red);
  });

  test('светофор ставится на пересечении с крупной дорогой, 4 въезда', () {
    final signals = TrafficSignals.fromNetwork(TrafficNetwork(_cross()));
    expect(signals.intersections, hasLength(1));
    expect(signals.intersections.single.nodeIds, {'c'});
    expect(signals.approaches, hasLength(4));
    expect(signals.lightForEdge('c', 's'), isNull); // на s светофора нет
  });

  test('двойной перекрёсток OSM — один светофор с общим циклом', () {
    // Крупная дорога раздваивается: узлы c1 и c2 в 15 м друг от друга.
    final graph = RoadGraph(
      nodes: {
        'n': const RoadGraphNode(id: 'n', x: 0, z: -150),
        'c1': const RoadGraphNode(id: 'c1', x: 0, z: 0),
        'c2': const RoadGraphNode(id: 'c2', x: 0, z: 15),
        's': const RoadGraphNode(id: 's', x: 0, z: 150),
        'w': const RoadGraphNode(id: 'w', x: -150, z: 0),
        'e': const RoadGraphNode(id: 'e', x: 150, z: 15),
      },
      edges: const [
        RoadGraphEdge(from: 'n', to: 'c1', highway: 'tertiary', oneway: false),
        RoadGraphEdge(from: 'c1', to: 'c2', highway: 'tertiary', oneway: false),
        RoadGraphEdge(from: 'c2', to: 's', highway: 'tertiary', oneway: false),
        RoadGraphEdge(from: 'w', to: 'c1', highway: 'residential', oneway: false),
        RoadGraphEdge(from: 'c2', to: 'e', highway: 'residential', oneway: false),
      ],
    );
    final signals = TrafficSignals.fromNetwork(TrafficNetwork(graph));
    expect(signals.intersections, hasLength(1));
    // Между узлами одного перекрёстка светофора нет — машина не встанет посреди.
    expect(signals.lightForEdge('c1', 'c2'), isNull);
  });

  test('машина стоит у стоп-линии на красный и проезжает на зелёный', () {
    final network = TrafficNetwork(_cross());
    final signals = TrafficSignals.fromNetwork(network);
    final intersection = signals.intersections.single;
    // Едем с запада на восток (поперёк крупной дороги). Время подбираем так,
    // чтобы у нас был красный ещё 10+ секунд.
    final eastbound = vm.Vector3(1, 0, 0);
    signals.time = 0;
    while (intersection.lightFor(eastbound, signals.time) != SignalLight.red ||
        intersection.lightFor(eastbound, signals.time + 12) != SignalLight.red) {
      signals.time += 0.5;
    }

    final car = TrafficCar(
      position: vm.Vector3(-60, 0, trafficLaneOffset),
      heading: math.pi / 2,
      fromNodeId: 'w',
      toNodeId: 'c',
      nextNodeId: 'e',
    );
    final random = math.Random(1);
    for (var i = 0; i < 12 * 60; i++) {
      stepTrafficCar(car, network, dt: 1 / 60, random: random, signals: signals);
      signals.advance(1 / 60);
    }
    expect(car.speed, closeTo(0, 0.01));
    expect(car.position.x, lessThan(-signalStopLineBack + 0.6));
    expect(car.position.x, greaterThan(-signalStopLineBack - 3));

    for (var i = 0; i < 30 * 60; i++) {
      stepTrafficCar(car, network, dt: 1 / 60, random: random, signals: signals);
      signals.advance(1 / 60);
    }
    expect(car.position.x, greaterThan(20)); // дождался зелёного и уехал
  });

  test('проезд на красный ловится один раз за въезд', () {
    final signals = TrafficSignals.fromNetwork(TrafficNetwork(_cross()));
    final intersection = signals.intersections.single;
    final eastbound = vm.Vector2(10, 0);
    signals.time = 0;
    while (intersection.lightFor(vm.Vector3(1, 0, 0), signals.time) != SignalLight.red) {
      signals.time += 0.5;
    }
    final detector = RedLightDetector(signals);
    expect(detector.update(vm.Vector3(-20, 0, 1.5), eastbound), isFalse); // ещё не въехал
    expect(detector.update(vm.Vector3(-5, 0, 1.5), eastbound), isTrue); // въехал на красный
    expect(detector.update(vm.Vector3(0, 0, 1.5), eastbound), isFalse); // внутри — второй раз не считаем
    expect(detector.update(vm.Vector3(20, 0, 1.5), eastbound), isFalse);
  });

  test('на зелёный проезд не считается нарушением', () {
    final signals = TrafficSignals.fromNetwork(TrafficNetwork(_cross()));
    final intersection = signals.intersections.single;
    signals.time = 0;
    while (intersection.lightFor(vm.Vector3(1, 0, 0), signals.time) != SignalLight.green) {
      signals.time += 0.5;
    }
    final detector = RedLightDetector(signals);
    expect(detector.update(vm.Vector3(-5, 0, 1.5), vm.Vector2(10, 0)), isFalse);
  });
}
