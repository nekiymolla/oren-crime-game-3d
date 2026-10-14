import 'dart:math' as math;

import 'package:crime_oren/traffic/traffic_car.dart';
import 'package:crime_oren/world/road_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

RoadGraph _graph(Map<String, (double, double)> nodes, List<(String, String)> edges, {bool oneway = false, String highway = 'residential'}) {
  return RoadGraph(
    nodes: {
      for (final entry in nodes.entries)
        entry.key: RoadGraphNode(id: entry.key, x: entry.value.$1, z: entry.value.$2),
    },
    edges: [
      for (final (from, to) in edges) RoadGraphEdge(from: from, to: to, highway: highway, oneway: oneway),
    ],
  );
}

/// Квартал 80x80: по нему машина может кружить бесконечно.
RoadGraph _block() => _graph(
  {'a': (0, 0), 'b': (0, 80), 'c': (80, 80), 'd': (80, 0)},
  [('a', 'b'), ('b', 'c'), ('c', 'd'), ('d', 'a')],
);

TrafficCar _carAt(TrafficNetwork network, String from, String to) {
  final a = network.graph.nodes[from]!;
  final b = network.graph.nodes[to]!;
  final direction = (b.toVector3() - a.toVector3()).normalized();
  return TrafficCar(
    position: a.toVector3() + rightOf(direction) * trafficLaneOffset,
    heading: math.atan2(direction.x, direction.z),
    fromNodeId: from,
    toNodeId: to,
  );
}

void _drive(TrafficCar car, TrafficNetwork network, double seconds, {List<TrafficObstacle> obstacles = const [], void Function()? onStep}) {
  final random = math.Random(7);
  for (var i = 0; i < (seconds * 60).round(); i++) {
    stepTrafficCar(car, network, dt: 1 / 60, random: random, obstacles: obstacles);
    onStep?.call();
  }
}

/// Расстояние в плане от точки до отрезка.
double _distanceToSegment(vm.Vector3 p, vm.Vector3 a, vm.Vector3 b) {
  final ab = b - a;
  final t = ((p - a).dot(ab) / ab.length2).clamp(0.0, 1.0);
  final closest = a + ab * t;
  return vm.Vector2(p.x - closest.x, p.z - closest.z).length;
}

void main() {
  test('по прямой едет по правой полосе с крейсерской скоростью', () {
    final network = TrafficNetwork(_graph({'a': (0, 0), 'b': (0, 200)}, [('a', 'b')]));
    final car = _carAt(network, 'a', 'b');
    _drive(car, network, 6.0);
    // Курс +Z, правая рука — на -X.
    expect(car.position.x, closeTo(-trafficLaneOffset, 0.05));
    expect(car.speed, closeTo(9.0, 0.1));
  });

  test('тормозит и встаёт перед препятствием в своей полосе', () {
    final network = TrafficNetwork(_graph({'a': (0, 0), 'b': (0, 200)}, [('a', 'b')]));
    final car = _carAt(network, 'a', 'b');
    final obstacle = (position: vm.Vector3(-trafficLaneOffset, 0, 50), radius: 0.9);
    _drive(car, network, 15.0, obstacles: [obstacle]);
    expect(car.speed, closeTo(0.0, 0.01));
    final gap = 50 - car.position.z;
    expect(gap, greaterThan(obstacle.radius + 2.0)); // не впритык
    expect(gap, lessThan(obstacle.radius + TrafficDriving.stopGap + 1.0)); // и не за версту
  });

  test('встречку не замечает — едет мимо', () {
    final network = TrafficNetwork(_graph({'a': (0, 0), 'b': (0, 200)}, [('a', 'b')]));
    final car = _carAt(network, 'a', 'b');
    _drive(car, network, 10.0, obstacles: [(position: vm.Vector3(trafficLaneOffset, 0, 50), radius: 0.9)]);
    expect(car.position.z, greaterThan(60.0));
  });

  test('перед поворотом на 90° сбрасывает скорость и встаёт в новую полосу', () {
    final network = TrafficNetwork(
      _graph({'a': (0, 0), 'b': (0, 60), 'c': (100, 60)}, [('a', 'b'), ('b', 'c')], oneway: false),
    );
    final car = _carAt(network, 'a', 'b')..nextNodeId = 'c';
    var minSpeedNearCorner = double.infinity;
    _drive(car, network, 14.0, onStep: () {
      if ((car.position - vm.Vector3(0, 0, 60)).length < 8) {
        minSpeedNearCorner = math.min(minSpeedNearCorner, car.speed);
      }
    });
    expect(minSpeedNearCorner, lessThan(9.0 * 0.7));
    expect(car.toNodeId, 'c');
    // Курс +X, правая рука — на +Z: полоса на z = 60 + 1.5.
    expect(car.position.x, greaterThan(30.0));
    expect(car.position.z, closeTo(60 + trafficLaneOffset, 0.3));
  });

  test('по кварталу кружит минутами и не уходит с дороги', () {
    final network = TrafficNetwork(_block());
    final car = _carAt(network, 'a', 'b');
    final segments = [
      (vm.Vector3(0, 0, 0), vm.Vector3(0, 0, 80)),
      (vm.Vector3(0, 0, 80), vm.Vector3(80, 0, 80)),
      (vm.Vector3(80, 0, 80), vm.Vector3(80, 0, 0)),
      (vm.Vector3(80, 0, 0), vm.Vector3(0, 0, 0)),
    ];
    var worst = 0.0;
    _drive(car, network, 120.0, onStep: () {
      final offRoad = segments.map((s) => _distanceToSegment(car.position, s.$1, s.$2)).reduce(math.min);
      worst = math.max(worst, offRoad);
    });
    // Дорога residential — примерно 3 м от оси в каждую сторону.
    expect(worst, lessThan(3.0));
    expect(car.stoppedSeconds, 0.0);
  });

  test('сеть трафика не включает service и уважает oneway', () {
    final graph = RoadGraph(
      nodes: {
        'a': const RoadGraphNode(id: 'a', x: 0, z: 0),
        'b': const RoadGraphNode(id: 'b', x: 0, z: 10),
        'c': const RoadGraphNode(id: 'c', x: 10, z: 10),
      },
      edges: const [
        RoadGraphEdge(from: 'a', to: 'b', highway: 'tertiary', oneway: true),
        RoadGraphEdge(from: 'b', to: 'c', highway: 'service', oneway: false),
      ],
    );
    final network = TrafficNetwork(graph);
    expect(network.adjacency['a'], ['b']);
    expect(network.adjacency['b'], isNull); // назад нельзя, во двор незачем
    // На односторонней — по оси, без сдвига.
    expect(network.lanePoint('a', 'b').x, closeTo(0, 1e-9));
  });

  test('в тупике разворачивается', () {
    final network = TrafficNetwork(_graph({'a': (0, 0), 'b': (0, 60)}, [('a', 'b')]));
    final random = math.Random(1);
    expect(network.pickNext('a', 'b', random), 'a');
  });
}
