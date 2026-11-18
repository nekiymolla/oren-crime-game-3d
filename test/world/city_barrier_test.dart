import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:crime_oren/world/city_barrier.dart';
import 'package:crime_oren/world/city_map.dart';

void main() {
  final fence = CityBarrier(
    a: vm.Vector2(-3, 0),
    b: vm.Vector2(3, 0),
    y: 0,
    height: 1.6,
  );
  test('railing envelope stops a body between its decorative pickets', () {
    final hit = fence.cast(vm.Vector3(.13, .9, -2), vm.Vector3(0, 0, 1), 4)!;
    expect(hit.distance, closeTo(1.96, 1e-6));
    expect(hit.normal.z, -1);
    expect(fence.cast(vm.Vector3(0, 2, -2), vm.Vector3(0, 0, 1), 4), isNull);
    expect(fence.cast(vm.Vector3(0, .9, -2), vm.Vector3(0, 0, 1), 1), isNull);
  });
  test('diagonal fence preserves world distance and normal', () {
    final diagonal = CityBarrier(
      a: vm.Vector2(0, 0),
      b: vm.Vector2(4, 4),
      y: 0,
      height: 1.2,
    );
    final normal = vm.Vector3(-1, 0, 1).normalized();
    final hit = diagonal.cast(vm.Vector3(2, .8, 2) + normal * 2, -normal, 4)!;
    expect(hit.distance, closeTo(1.96, 1e-6));
    expect(hit.normal.dot(normal), closeTo(1, 1e-6));
  });
  test('parallel rays miss outside and an inside origin has a finite hit', () {
    expect(fence.cast(vm.Vector3(0, .9, -2), vm.Vector3(1, 0, 0), 10), isNull);
    final hit = fence.cast(vm.Vector3(0, .9, 0), vm.Vector3(0, 0, 1), 1)!;
    expect(hit.distance, 0);
    expect(hit.normal.length, closeTo(1, 1e-9));
  });
  test('every authored area entrance has a clear pedestrian corridor', () {
    final data =
        jsonDecode(File('assets/data/city_map.json').readAsStringSync())
            as Map<String, dynamic>;
    final map = CityMap.fromJson(data);
    for (final raw in data['barriers']) {
      for (final entry in raw['gates'] ?? [raw['gate']]) {
        final gate = entry is List ? entry : entry['point'];
        final area = [
          ...data['areas'],
          ...data['startBlock']['buildings'],
        ].firstWhere((a) => (a['osm'] ?? a['basis']) == raw['basis']);
        final center = vm.Vector3(
          (area['center'][0] as num).toDouble(),
          .9,
          (area['center'][1] as num).toDouble(),
        );
        final g = vm.Vector3(
          (gate[0] as num).toDouble(),
          .9,
          (gate[1] as num).toDouble(),
        );
        final direction = (center - g).normalized();
        final right = vm.Vector3(-direction.z, 0, direction.x);
        for (final offset in [-.6, 0.0, .6]) {
          expect(
            map.castBarriers(
              g - direction * 1.2 + right * offset,
              direction,
              2.4,
            ),
            isNull,
            reason: raw['basis'],
          );
        }
      }
    }
  });
}
