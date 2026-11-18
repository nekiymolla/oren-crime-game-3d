import 'dart:math' as math;
import 'package:vector_math/vector_math.dart' as vm;
import '../player/character_motion.dart' show CharacterRaycaster;

class VehicleSweepHit {
  const VehicleSweepHit(this.fraction, this.normal);
  final double fraction;
  final vm.Vector3 normal;
}

/// Sweep the four corners and edge centres through translation AND rotation.
/// Bumper-only probes miss side impacts and corners swinging into a wall.
VehicleSweepHit? sweepVehicleHull({
  required vm.Vector3 position,
  required vm.Vector3 displacement,
  required double oldHeading,
  required double newHeading,
  required double halfWidth,
  required double halfLength,
  required double probeHeight,
  required CharacterRaycaster cast,
}) {
  var fraction = 1.0;
  vm.Vector3? normal;
  final s0 = math.sin(oldHeading), c0 = math.cos(oldHeading);
  final s1 = math.sin(newHeading), c1 = math.cos(newHeading);
  for (final (x, z) in [
    (-halfWidth, -halfLength),
    (0.0, -halfLength),
    (halfWidth, -halfLength),
    (-halfWidth, 0.0),
    (halfWidth, 0.0),
    (-halfWidth, halfLength),
    (0.0, halfLength),
    (halfWidth, halfLength),
  ]) {
    final start =
        position + vm.Vector3(x * c0 + z * s0, probeHeight, -x * s0 + z * c0);
    final end =
        position +
        displacement +
        vm.Vector3(x * c1 + z * s1, probeHeight, -x * s1 + z * c1);
    final delta = end - start;
    final length = delta.length;
    if (length < 1e-7) continue;
    final hit = cast(start, delta / length, length);
    if (hit == null || hit.distance < 0 || hit.distance > length) continue;
    final safe = ((hit.distance - .025) / length).clamp(0.0, 1.0);
    if (safe < fraction) {
      fraction = safe;
      normal = hit.normal;
    }
  }
  return normal == null ? null : VehicleSweepHit(fraction, normal);
}
