import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crime_oren/traffic/traffic_car.dart';
import 'package:crime_oren/world/road_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Симуляция потока на НАСТОЯЩЕМ графе Южного района (assets/data/road_graph.json)
/// — глазами по скриншотам не видно ни наложений кузовов, ни вечных пробок
/// на перекрёстках, а здесь это меряется за секунды.
void main() {
  final graph = RoadGraph.fromJson(
    jsonDecode(File('assets/data/road_graph.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final network = TrafficNetwork(graph);

  /// Расстояние от машины до оси ближайшего ребра трафика.
  double distanceToRoad(vm.Vector3 p) {
    var best = double.infinity;
    for (final entry in network.adjacency.entries) {
      final a = graph.nodes[entry.key]!;
      for (final toId in entry.value) {
        final b = graph.nodes[toId]!;
        final abx = b.x - a.x, abz = b.z - a.z;
        final length2 = abx * abx + abz * abz;
        final t = length2 == 0
            ? 0.0
            : (((p.x - a.x) * abx + (p.z - a.z) * abz) / length2).clamp(
                0.0,
                1.0,
              );
        final dx = a.x + abx * t - p.x, dz = a.z + abz * t - p.z;
        best = math.min(best, math.sqrt(dx * dx + dz * dz));
      }
    }
    return best;
  }

  List<TrafficCar> spawn(math.Random random, int count) {
    final starts = network.adjacency.keys.where((id) {
      final n = graph.nodes[id]!;
      return n.x.abs() < 250 && n.z.abs() < 250; // центр района, где плотно
    }).toList();
    final cars = <TrafficCar>[];
    while (cars.length < count) {
      final fromId = starts[random.nextInt(starts.length)];
      final exits = network.adjacency[fromId]!;
      final toId = exits[random.nextInt(exits.length)];
      final from = graph.nodes[fromId]!.toVector3();
      final direction = graph.nodes[toId]!.toVector3() - from;
      if (direction.length2 < 1e-6) continue;
      direction.normalize();
      final oneway = network.edge(fromId, toId)!.oneway;
      final position =
          from +
          (oneway ? vm.Vector3.zero() : rightOf(direction) * trafficLaneOffset);
      if (cars.any((c) => (c.position - position).length < 15)) continue;
      cars.add(
        TrafficCar(
          position: position,
          heading: math.atan2(direction.x, direction.z),
          fromNodeId: fromId,
          toNodeId: toId,
          priority: cars.length,
        ),
      );
    }
    return cars;
  }

  for (final (seed, count) in [(42, 10), (7, 15), (2026, 15)]) {
    test(
      '$count машин 5 минут по району (сид $seed): на дороге, без наложений, без вечных пробок',
      () {
        final random = math.Random(seed);
        final cars = spawn(random, count);
        const dt = 1 / 30;
        var worstOffRoad = 0.0;
        var closest = double.infinity;
        var maxStopped = 0.0;
        String? worstOffRoadInfo;

        for (var step = 0; step < 5 * 60 * 30; step++) {
          for (final car in cars) {
            stepTrafficCar(car, network, dt: dt, random: random, traffic: cars);
            maxStopped = math.max(maxStopped, car.stoppedSeconds);
          }
          if (step % 15 == 0) {
            for (final car in cars) {
              final off = distanceToRoad(car.position);
              if (off > worstOffRoad) {
                worstOffRoad = off;
                worstOffRoadInfo =
                    '${car.position} ${car.fromNodeId}->${car.toNodeId}';
              }
            }
          }
          for (var i = 0; i < cars.length; i++) {
            for (var j = i + 1; j < cars.length; j++) {
              closest = math.min(
                closest,
                (cars[i].position - cars[j].position).length,
              );
            }
          }
        }

        for (final car in cars.where((c) => c.stoppedSeconds > 30)) {
          // ignore: avoid_print
          print('СТОИТ prio=${car.priority} ${car.fromNodeId}->${car.toNodeId}->${car.nextNodeId} '
              'pos=${car.position} hdg=${car.heading.toStringAsFixed(2)} uturn=${car.isTurningAround}');
          for (final other in cars) {
            if (identical(other, car)) continue;
            final rel = other.position - car.position;
            if (rel.length > 25) continue;
            final along = rel.dot(car.forward);
            final lateral = rel.dot(rightOf(car.forward));
            // ignore: avoid_print
            print('   рядом prio=${other.priority} along=${along.toStringAsFixed(1)} lat=${lateral.toStringAsFixed(1)} '
                'hdg=${other.heading.toStringAsFixed(2)} stopped=${other.stoppedSeconds.toStringAsFixed(0)} ${other.fromNodeId}->${other.toNodeId}');
          }
        }
        // ignore: avoid_print
        print(
          'съезд с оси макс ${worstOffRoad.toStringAsFixed(2)} м ($worstOffRoadInfo), '
          'ближе всего машины ${closest.toStringAsFixed(2)} м, дольше всего стояла ${maxStopped.toStringAsFixed(1)} с',
        );
        expect(worstOffRoad, lessThan(4.0));
        expect(closest, greaterThan(2.0));
        expect(maxStopped, lessThan(30.0));
      },
    );
  }
}
