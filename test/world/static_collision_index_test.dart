import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:crime_oren/world/static_collision_index.dart';

void main() {
  test(
    'BVH finds nearest two-sided surfaces and handles parallel/inside rays',
    () {
      final index = StaticCollisionIndex.build(
        Float32List.fromList([
          -2,
          -2,
          5,
          2,
          -2,
          5,
          0,
          2,
          5,
          -2,
          -2,
          2,
          2,
          -2,
          2,
          0,
          2,
          2,
        ]),
      );
      final hit = index.cast(vm.Vector3.zero(), vm.Vector3(0, 0, 1), 10)!;
      expect(hit.distance, closeTo(2, 1e-8));
      expect(hit.normal.z, -1);
      expect(
        index.cast(vm.Vector3(0, 0, 3), vm.Vector3(0, 0, -1), 10)!.distance,
        closeTo(1, 1e-8),
      );
      expect(index.cast(vm.Vector3.zero(), vm.Vector3(0, 0, 1), 1), isNull);
      expect(index.cast(vm.Vector3.zero(), vm.Vector3(1, 0, 0), 10), isNull);
    },
  );
  test('spatial splits retain every triangle across a dense grid', () {
    final data = <double>[];
    for (var x = -20; x <= 20; x++) {
      for (var z = -20; z <= 20; z++) {
        data.addAll([
          x.toDouble(),
          0,
          z.toDouble(),
          x + 1.0,
          0,
          z.toDouble(),
          x.toDouble(),
          0,
          z + 1.0,
        ]);
      }
    }
    final index = StaticCollisionIndex.build(Float32List.fromList(data));
    final random = math.Random(42);
    for (var i = 0; i < 500; i++) {
      final x = random.nextInt(40) - 20 + .2, z = random.nextInt(40) - 20 + .2;
      expect(
        index.cast(vm.Vector3(x, 3, z), vm.Vector3(0, -1, 0), 5)!.distance,
        closeTo(3, 1e-7),
      );
    }
  });
  test('empty index misses safely', () {
    expect(
      StaticCollisionIndex.build(
        Float32List(0),
      ).cast(vm.Vector3.zero(), vm.Vector3(0, 1, 0), 5),
      isNull,
    );
  });
}
