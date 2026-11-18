import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:crime_oren/player/camera_obstruction.dart';

void main() {
  final target = vm.Vector3(0, 1.5, 0);
  final eye = vm.Vector3(0, 2.5, -6);

  test('open space preserves the camera arm', () {
    final result = resolveCameraObstruction(
      target: target,
      eye: eye,
      raycast: (_, _, _) => null,
    );
    expect((result - eye).length, lessThan(1e-6));
  });

  test('wall pulls the camera in with near-plane clearance', () {
    final result = resolveCameraObstruction(
      target: target,
      eye: eye,
      raycast: (origin, direction, reach) {
        final distance = (-2 - origin.z) / direction.z;
        return distance >= 0 && distance <= reach ? distance : null;
      },
    );
    expect(result.z, greaterThan(-1.8));
    expect(result.z, lessThan(-1.5));
  });

  test('offset probes catch a doorway edge missed by the centre ray', () {
    final result = resolveCameraObstruction(
      target: target,
      eye: eye,
      raycast: (origin, direction, reach) {
        if (origin.x < 0.15) return null;
        return 2;
      },
    );
    expect((result - target).length, closeTo(1.78, 1e-6));
  });

  test('a wall at the pivot cannot push the camera through the player', () {
    final result = resolveCameraObstruction(
      target: target,
      eye: eye,
      raycast: (_, _, _) => 0.01,
    );
    expect((result - target).length, closeTo(0, 1e-6));
    expect(result.x.isFinite && result.y.isFinite && result.z.isFinite, isTrue);
  });
}
