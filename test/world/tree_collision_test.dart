import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:crime_oren/world/tree_collision.dart';
import 'package:crime_oren/player/character_motion.dart';

void main() {
  TreeTrunkHit? cast(
    vm.Vector3 origin,
    vm.Vector3 direction,
    double distance, {
    double scale = 1,
    double sweep = 0,
  }) => raycastTreeTrunk(
    origin: origin,
    direction: direction,
    maxDistance: distance,
    root: vm.Vector3.zero(),
    scale: scale,
    sweepRadius: sweep,
  );

  test('trunk ray returns the near side and an outward unit normal', () {
    final hit = cast(vm.Vector3(0, 0.9, -3), vm.Vector3(0, 0, 1), 5)!;
    expect(hit.distance, closeTo(3 - treeTrunkRadius, 1e-6));
    expect(hit.normal.z, closeTo(-1, 1e-6));
    expect(cast(vm.Vector3(0, 0.9, -3), vm.Vector3(0, 0, -1), 5), isNull);
    expect(cast(vm.Vector3(0, 0.9, -3), vm.Vector3(0, 0, 1), 1), isNull);
  });

  test('height, scale and vertical ground probes are respected', () {
    expect(cast(vm.Vector3(0, 4, -3), vm.Vector3(0, 0, 1), 5), isNull);
    expect(cast(vm.Vector3(0, -1, -3), vm.Vector3(0, 0, 1), 5), isNull);
    expect(cast(vm.Vector3(0, 1, 0), vm.Vector3(0, -1, 0), 5), isNull);
    final hit = cast(vm.Vector3(0, 0.9, -3), vm.Vector3(0, 0, 1), 5, scale: 2)!;
    expect(hit.distance, closeTo(3 - 2 * treeTrunkRadius, 1e-6));
  });

  test('an overlapping spawn gets a finite outward escape normal', () {
    final hit = cast(vm.Vector3(0, 1, 0), vm.Vector3(1, 0, 0), 1)!;
    expect(hit.distance, 0);
    expect(hit.normal.x, -1);
  });

  test('bumper sweep catches a trunk between the old point probes', () {
    final origin = vm.Vector3(0.45, 0.5, -3);
    final direction = vm.Vector3(0, 0, 1);
    expect(cast(origin, direction, 5), isNull);
    expect(cast(origin, direction, 5, sweep: 0.9), isNotNull);
  });

  test('running at a trunk from every angle does not cross its body', () {
    for (var degrees = 0; degrees < 360; degrees += 10) {
      final angle = degrees * math.pi / 180;
      final motion =
          CharacterMotion(
            position: vm.Vector3(math.sin(angle) * 3, 0, math.cos(angle) * 3),
            raycast: (origin, direction, distance) {
              final hit = cast(origin, direction, distance);
              return hit == null
                  ? null
                  : CharacterRayHit(distance: hit.distance, normal: hit.normal);
            },
          )..setMoveInput(
            vm.Vector2(-math.sin(angle), -math.cos(angle)),
            isRunning: true,
          );
      for (var i = 0; i < 180; i++) {
        motion.step(1 / 60);
        final clearance = math.sqrt(
          motion.position.x * motion.position.x +
              motion.position.z * motion.position.z,
        );
        expect(clearance, greaterThan(0.66), reason: 'angle $degrees frame $i');
      }
    }
  });
}
