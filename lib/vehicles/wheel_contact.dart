import 'dart:math' as math;
import 'package:vector_math/vector_math.dart' as vm;

/// A least-squares support plane through four tyre contact heights. The
/// residual at each wheel is handled by its individual suspension offset.
class WheelContact {
  const WheelContact(this.height, this.pitch, this.roll, this.heights);
  final double height, pitch, roll;
  final List<double> heights;

  static WheelContact sample({
    required double x,
    required double z,
    required double heading,
    required List<vm.Vector3> anchors,
    required double Function(double x, double z) heightAt,
  }) {
    assert(anchors.length == 4);
    final sin = math.sin(heading), cos = math.cos(heading);
    final heights = <double>[
      for (final a in anchors)
        heightAt(x + a.x * cos + a.z * sin, z - a.x * sin + a.z * cos),
    ];
    final mx = anchors.fold(0.0, (s, p) => s + p.x) / 4;
    final mz = anchors.fold(0.0, (s, p) => s + p.z) / 4;
    final mh = heights.reduce((a, b) => a + b) / 4;
    var xx = 0.0, zz = 0.0, xz = 0.0, xh = 0.0, zh = 0.0;
    for (var i = 0; i < 4; i++) {
      final dx = anchors[i].x - mx,
          dz = anchors[i].z - mz,
          dh = heights[i] - mh;
      xx += dx * dx;
      zz += dz * dz;
      xz += dx * dz;
      xh += dx * dh;
      zh += dz * dh;
    }
    final determinant = xx * zz - xz * xz;
    final slopeX = determinant.abs() < 1e-8
        ? 0.0
        : (xh * zz - zh * xz) / determinant;
    final slopeZ = determinant.abs() < 1e-8
        ? 0.0
        : (zh * xx - xh * xz) / determinant;
    return WheelContact(
      mh - slopeX * mx - slopeZ * mz,
      -math.atan(slopeZ),
      math.atan(slopeX),
      heights,
    );
  }
}
