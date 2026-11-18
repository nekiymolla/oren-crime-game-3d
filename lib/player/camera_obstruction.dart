import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

typedef CameraObstructionRaycast =
    double? Function(
      vm.Vector3 origin,
      vm.Vector3 direction,
      double maxDistance,
    );

/// Shortens the camera arm against walls and ceilings. Offset probes leave
/// space for the near plane, even when the centre ray misses a doorway edge.
vm.Vector3 resolveCameraObstruction({
  required vm.Vector3 target,
  required vm.Vector3 eye,
  required CameraObstructionRaycast raycast,
  double radius = 0.22,
}) {
  final arm = eye - target;
  final length = arm.length;
  if (length < 1e-6) return eye.clone();
  final direction = arm / length;
  var right = direction.cross(vm.Vector3(0, 1, 0));
  if (right.length2 < 1e-6) right = vm.Vector3(1, 0, 0);
  right.normalize();
  final up = right.cross(direction).normalized();
  var distance = length;
  for (final offset in [
    vm.Vector3.zero(),
    right * radius,
    right * -radius,
    up * radius,
    up * -radius,
  ]) {
    final hit = raycast(target + offset, direction, length + radius);
    if (hit != null) distance = math.min(distance, math.max(0.0, hit - radius));
  }
  return target + direction * distance;
}
