import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

class TreeTrunkHit {
  const TreeTrunkHit(this.distance, this.normal);

  final double distance;
  final vm.Vector3 normal;
}

/// Conservative envelope of the slightly bent lower trunk, in metres.
const double treeTrunkRadius = 0.28;
const double treeTrunkHeight = 2.5;

/// Side surface of a finite upright cylinder. Pure math; never traverses
/// leaves or render meshes. Vertical ground probes intentionally ignore it.
/// [sweepRadius] inflates the trunk for a rounded vehicle bumper sweep.
TreeTrunkHit? raycastTreeTrunk({
  required vm.Vector3 origin,
  required vm.Vector3 direction,
  required double maxDistance,
  required vm.Vector3 root,
  double scale = 1,
  double sweepRadius = 0,
}) {
  final a = direction.x * direction.x + direction.z * direction.z;
  if (a < 1e-10 || maxDistance < 0 || scale <= 0) return null;
  final radius = treeTrunkRadius * scale + sweepRadius;
  final x = origin.x - root.x;
  final z = origin.z - root.z;
  final c = x * x + z * z - radius * radius;
  var distance = 0.0;
  if (c > 0) {
    final b = x * direction.x + z * direction.z;
    if (b >= 0) return null;
    final discriminant = b * b - a * c;
    if (discriminant < 0) return null;
    distance = (-b - math.sqrt(discriminant)) / a;
  }
  if (distance > maxDistance) return null;
  final y = origin.y + direction.y * distance;
  if (y < root.y || y > root.y + treeTrunkHeight * scale) return null;
  var normal = vm.Vector3(
    x + direction.x * distance,
    0,
    z + direction.z * distance,
  );
  if (normal.length2 < 1e-10) {
    normal = vm.Vector3(-direction.x, 0, -direction.z);
  }
  return TreeTrunkHit(distance, normal.normalized());
}
