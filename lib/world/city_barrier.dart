import 'dart:math' as math;
import 'package:vector_math/vector_math.dart' as vm;
import '../player/character_motion.dart' show CharacterRayHit;

/// A railing section uses a thin continuous collision envelope. Rendering
/// individual pickets must not let a body slip through the gaps between rays.
class CityBarrier {
  CityBarrier({
    required this.a,
    required this.b,
    required this.y,
    required this.height,
    this.thickness = .08,
  }) : length = (b - a).length,
       minX = math.min(a.x, b.x) - thickness,
       maxX = math.max(a.x, b.x) + thickness,
       minZ = math.min(a.y, b.y) - thickness,
       maxZ = math.max(a.y, b.y) + thickness;
  final vm.Vector2 a, b;
  final double y, height, thickness, length, minX, maxX, minZ, maxZ;

  CharacterRayHit? cast(vm.Vector3 origin, vm.Vector3 direction, double reach) {
    if (length < 1e-6 || reach < 0) return null;
    final end = origin + direction * reach;
    if (math.max(origin.x, end.x) < minX ||
        math.min(origin.x, end.x) > maxX ||
        math.max(origin.z, end.z) < minZ ||
        math.min(origin.z, end.z) > maxZ) {
      return null;
    }
    final ux = (b.x - a.x) / length, uz = (b.y - a.y) / length;
    final ox = origin.x - a.x, oz = origin.z - a.y;
    final o = [ox * ux + oz * uz, origin.y - y, -ox * uz + oz * ux];
    final d = [
      direction.x * ux + direction.z * uz,
      direction.y,
      -direction.x * uz + direction.z * ux,
    ];
    final lows = [0.0, 0.0, -thickness / 2],
        highs = [length, height, thickness / 2];
    var enter = 0.0, exit = reach;
    var normal = vm.Vector3.zero();
    final axes = [
      vm.Vector3(ux, 0, uz),
      vm.Vector3(0, 1, 0),
      vm.Vector3(-uz, 0, ux),
    ];
    for (var i = 0; i < 3; i++) {
      if (d[i].abs() < 1e-9) {
        if (o[i] < lows[i] || o[i] > highs[i]) return null;
        continue;
      }
      var near = (lows[i] - o[i]) / d[i], far = (highs[i] - o[i]) / d[i];
      var sign = -1.0;
      if (near > far) {
        final swap = near;
        near = far;
        far = swap;
        sign = 1;
      }
      if (near > enter) {
        enter = near;
        normal = axes[i] * sign;
      }
      exit = math.min(exit, far);
      if (enter > exit) return null;
    }
    if (normal.length2 < 1e-10) {
      if (direction.length2 < 1e-10) return null;
      normal = -direction.normalized();
    }
    return CharacterRayHit(distance: enter, normal: normal);
  }
}
