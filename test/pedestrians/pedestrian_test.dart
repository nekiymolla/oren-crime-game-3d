import 'dart:math';
import 'dart:typed_data';

import 'package:crime_oren/pedestrians/pedestrian.dart';
import 'package:crime_oren/traffic/traffic_car.dart';
import 'package:crime_oren/world/nav_grid.dart';
import 'package:crime_oren/world/road_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Сетка 60x60 м с началом в (0,0): дом x 20..30, z 20..30; крупная дорога
/// — полоса z 40..46 во всю ширину; мелкая — полоса x 50..54.
NavGrid _grid() {
  const w = 60, h = 60;
  final cells = Uint8List(w * h);
  for (var z = 0; z < h; z++) {
    for (var x = 0; x < w; x++) {
      var k = NavKind.ground;
      if (x >= 20 && x < 30 && z >= 20 && z < 30) k = NavKind.building;
      if (z >= 40 && z < 46) k = NavKind.majorRoad;
      if (x >= 50 && x < 54) k = NavKind.minorRoad;
      cells[z * w + x] = k.index;
    }
  }
  return NavGrid(minX: 0, minZ: 0, metersPerCell: 1, width: w, height: h, cells: cells);
}

void _walk(Pedestrian p, NavGrid grid, double seconds, {int seed = 1, void Function(Pedestrian)? each}) {
  final random = Random(seed);
  for (var t = 0.0; t < seconds; t += 1 / 30) {
    advancePedestrian(p, walkable: grid.isWalkable, solid: grid.isBuilding, dt: 1 / 30, speed: 1.3, random: random);
    each?.call(p);
  }
}

void main() {
  test('сетка: типы клеток, вне сетки — как дом', () {
    final grid = _grid();
    expect(grid.kindAt(25, 25), NavKind.building);
    expect(grid.isWalkable(5, 5), isTrue);
    expect(grid.isWalkable(5, 42), isFalse); // крупная дорога
    expect(grid.isWalkable(52, 5), isTrue); // мелкую переходить можно
    expect(grid.isDrivable(52, 5), isTrue);
    expect(grid.isDrivable(5, 5), isFalse);
    expect(grid.isBuilding(-1, 5), isTrue);
    expect(grid.badFraction(0, 43, 59, 43, grid.isDrivable), 0);
    expect(grid.badFraction(0, 10, 59, 10, grid.isDrivable), greaterThan(0.9));
  });

  test('за долгую прогулку — ни шагу в дом и на крупную дорогу', () {
    final grid = _grid();
    for (var seed = 0; seed < 20; seed++) {
      final p = Pedestrian(position: vm.Vector3(15, 0, 15), yaw: seed.toDouble());
      _walk(p, grid, 120, seed: seed, each: (p) {
        expect(grid.isBuilding(p.position.x, p.position.z), isFalse, reason: 'seed $seed: в доме ${p.position}');
        expect(grid.kindAt(p.position.x, p.position.z), isNot(NavKind.majorRoad), reason: 'seed $seed: на дороге ${p.position}');
      });
    }
  });

  test('бродит, а не стоит: за минуту уходит заметно', () {
    final grid = _grid();
    final p = Pedestrian(position: vm.Vector3(10, 0, 10));
    _walk(p, grid, 60);
    expect((p.position - vm.Vector3(10, 0, 10)).length, greaterThan(3));
  });

  test('упирается в стену — обходит, а не стоит', () {
    final grid = _grid();
    // Идёт прямо на дом (+X), дом в метре впереди.
    final p = Pedestrian(position: vm.Vector3(18.5, 0, 25), yaw: pi / 2)..wanderSeconds = 100;
    _walk(p, grid, 5);
    expect(grid.isBuilding(p.position.x, p.position.z), isFalse);
    expect((p.position - vm.Vector3(18.5, 0, 25)).length, greaterThan(1));
  });

  test('оказался на крупной дороге (выскочил из машины) — уходит с неё', () {
    final grid = _grid();
    final p = Pedestrian(position: vm.Vector3(10, 0, 43));
    _walk(p, grid, 10);
    expect(grid.kindAt(p.position.x, p.position.z), isNot(NavKind.majorRoad));
  });

  test('испуганный бежит прочь от стрелка и быстрее шага', () {
    final grid = _grid();
    final p = Pedestrian(position: vm.Vector3(10, 0, 10));
    p.scare(vm.Vector3(10, 0, 0));
    _walk(p, grid, 3);
    expect(p.position.z, greaterThan(10 + 1.3 * 3 * 1.5)); // прочь (+Z) и бегом
  });

  test('три пули пистолета в корпус убивают, мёртвый не ходит', () {
    final grid = _grid();
    final p = Pedestrian(position: vm.Vector3(5, 0, 5));
    final shooter = vm.Vector3(5, 0, -10);
    expect(p.takeDamage(34, shooter), isFalse);
    expect(p.panicSeconds, greaterThan(0));
    expect(p.takeDamage(34, shooter), isFalse);
    expect(p.takeDamage(34, shooter), isTrue);
    expect(p.isDead, isTrue);
    expect(p.isShootable, isFalse);
    expect(p.takeDamage(34, shooter), isFalse);
    final before = p.position.clone();
    _walk(p, grid, 1);
    expect(p.position, before);
    p.revive();
    expect(p.isDead, isFalse);
  });

  test('сбитый машиной отлетает, но не в стену дома', () {
    final grid = _grid();
    final p = Pedestrian(position: vm.Vector3(19, 0, 25));
    p.knockDown(vm.Vector3(15, 0, 25), 15); // летит на +X, в дом
    _walk(p, grid, 2);
    expect(grid.isBuilding(p.position.x, p.position.z), isFalse);
  });

  test('сеть трафика выкидывает полосу, задевающую не-асфальт', () {
    final graph = RoadGraph(
      nodes: {
        'a': const RoadGraphNode(id: 'a', x: 0, z: 0),
        'b': const RoadGraphNode(id: 'b', x: 0, z: 100),
        'c': const RoadGraphNode(id: 'c', x: 100, z: 0),
      },
      edges: const [
        RoadGraphEdge(from: 'a', to: 'b', highway: 'residential', oneway: false),
        RoadGraphEdge(from: 'a', to: 'c', highway: 'residential', oneway: false),
      ],
    );
    // "Асфальт" — только вдоль оси Z (x около 0).
    final network = TrafficNetwork(graph, laneIsClear: (from, to) => from.x.abs() < 5 && to.x.abs() < 5);
    expect(network.adjacency['a'], ['b']);
    expect(network.edge('a', 'c'), isNull);
    expect(network.rejectedLaneCount, 2);
  });
}
