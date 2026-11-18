import 'dart:math' as math;
import 'package:vector_math/vector_math.dart' as vm;
import '../player/character_motion.dart' show CharacterRaycaster;

class VehicleSweepHit {
  const VehicleSweepHit(
    this.fraction,
    this.normal, {
    this.point,
    this.collider,
  });
  final vm.Vector3? point;
  final Object? collider;
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
  vm.Vector3? normal, point;
  Object? collider;
  var contacts = 0;
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
      point = start + delta / length * hit.distance;
      collider = hit.collider;
      contacts = 1;
    } else if ((safe - fraction).abs() < .012 &&
        normal != null &&
        normal.dot(hit.normal) > .95 &&
        identical(collider, hit.collider)) {
      final p = start + delta / length * hit.distance;
      point = (point! * contacts.toDouble() + p) / (contacts + 1);
      contacts++;
    }
  }
  return normal == null
      ? null
      : VehicleSweepHit(fraction, normal, point: point, collider: collider);
}

/// Swept oriented hull against a small upright obstacle. Sampling is bounded
/// by surface travel (8 cm) and each first contact is refined by bisection.
/// Unlike a large circle at the bumper this does not stop a car a metre early.
VehicleSweepHit? sweepVehicleCircle({
  required vm.Vector3 position,
  required vm.Vector3 displacement,
  required double oldHeading,
  required double newHeading,
  required double halfWidth,
  required double halfLength,
  required vm.Vector3 circle,
  double radius = .28,
}) {
  final travel =
      displacement.length +
      (newHeading - oldHeading).abs() *
          math.sqrt(halfWidth * halfWidth + halfLength * halfLength);
  final count = math.max(1, (travel / .08).ceil());
  ({bool overlaps, vm.Vector3 normal}) sample(double t) {
    final yaw = oldHeading + (newHeading - oldHeading) * t,
        s = math.sin(yaw),
        c = math.cos(yaw);
    final dx = circle.x - position.x - displacement.x * t,
        dz = circle.z - position.z - displacement.z * t;
    final x = dx * c - dz * s, z = dx * s + dz * c;
    final nearX = x.clamp(-halfWidth, halfWidth),
        nearZ = z.clamp(-halfLength, halfLength);
    var nx = nearX - x, nz = nearZ - z;
    final distance2 = nx * nx + nz * nz;
    if (distance2 < 1e-10) {
      if (halfWidth - x.abs() < halfLength - z.abs()) {
        nx = x >= 0 ? -1 : 1;
        nz = 0;
      } else {
        nx = 0;
        nz = z >= 0 ? -1 : 1;
      }
    }
    final n = vm.Vector3(nx * c + nz * s, 0, -nx * s + nz * c).normalized();
    return (overlaps: distance2 <= radius * radius, normal: n);
  }

  final initial = sample(0);
  if (initial.overlaps) {
    if (displacement.dot(initial.normal) >= 0 &&
        (newHeading - oldHeading).abs() < 1e-6) {
      return null;
    }
    return VehicleSweepHit(
      0,
      initial.normal,
      point: circle + initial.normal * radius,
    );
  }
  for (var i = 1; i <= count; i++) {
    final hit = sample(i / count);
    if (!hit.overlaps) continue;
    var lo = (i - 1) / count, hi = i / count;
    for (var n = 0; n < 8; n++) {
      final mid = (lo + hi) / 2;
      if (sample(mid).overlaps) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    final normal = sample(hi).normal;
    return VehicleSweepHit(
      math.max(0, lo - .005 / math.max(travel, .001)),
      normal,
      point: circle + normal * radius,
    );
  }
  return null;
}
