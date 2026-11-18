import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' as vm;

/// CPU-side authored tree, independent of the renderer so bounds and the
/// geometry budget can be checked without a live GPU. Units are metres.
class TreeMeshData {
  final List<double> positions = [];
  final List<double> normals = [];
  final List<double> colors = [];

  int get triangleCount => positions.length ~/ 9;

  void triangle(vm.Vector3 a, vm.Vector3 b, vm.Vector3 c, vm.Vector3 color) {
    final normal = (b - a).cross(c - a).normalized();
    for (final p in [a, b, c]) {
      positions.addAll([p.x, p.y, p.z]);
      normals.addAll([normal.x, normal.y, normal.z]);
      colors.addAll([color.x, color.y, color.z, 1]);
    }
  }

  Float32List get vertexPositions => Float32List.fromList(positions);
  Float32List get vertexNormals => Float32List.fromList(normals);
  Float32List get vertexColors => Float32List.fromList(colors);
}

class TreeGeometryData {
  TreeGeometryData(this.branches, this.leaves);

  final TreeMeshData branches;
  final TreeMeshData leaves;
}

/// Irregular deciduous tree with visible forks and individual opaque leaves.
/// No alpha overdraw or separate draw call per branch/leaf is needed.
TreeGeometryData buildDeciduousTree({
  int seed = 73,
  int leavesPerCluster = 42,
}) {
  final rng = math.Random(seed);
  final branches = TreeMeshData();
  final leaves = TreeMeshData();
  final bark = vm.Vector3(0.24, 0.21, 0.17);
  final clusters = <vm.Vector3>[];

  void branch(vm.Vector3 from, vm.Vector3 to, double r0, double r1) {
    final direction = (to - from).normalized();
    final axis = direction.y.abs() > 0.95
        ? vm.Vector3(1, 0, 0)
        : vm.Vector3(0, 1, 0);
    final right = direction.cross(axis).normalized();
    final up = right.cross(direction).normalized();
    const sides = 7;
    for (var side = 0; side < sides; side++) {
      final a = side * math.pi * 2 / sides;
      final b = (side + 1) * math.pi * 2 / sides;
      final d0 = right * math.cos(a) + up * math.sin(a);
      final d1 = right * math.cos(b) + up * math.sin(b);
      final p0 = from + d0 * r0;
      final p1 = from + d1 * r0;
      if (from.y == 0) {
        p0.y = 0;
        p1.y = 0;
      }
      final p2 = to + d0 * r1;
      final p3 = to + d1 * r1;
      final color = bark * (0.78 + rng.nextDouble() * 0.4);
      branches.triangle(p0, p2, p1, color);
      branches.triangle(p1, p2, p3, color);
    }
  }

  var previous = vm.Vector3.zero();
  for (var i = 1; i <= 7; i++) {
    final next = vm.Vector3(
      0.13 * math.sin(i * 0.7),
      i * 0.98,
      0.09 * math.sin(i * 1.2),
    );
    branch(previous, next, 0.19 * (1 - (i - 1) / 8), 0.19 * (1 - i / 8));
    previous = next;
  }
  for (var i = 0; i < 10; i++) {
    final angle = i * 2.39996 + rng.nextDouble() * 0.25;
    final height = 2.5 + i * 0.32;
    final spread = 1.6 + rng.nextDouble() * 0.3;
    final origin = vm.Vector3(0.1 * math.sin(height), height, 0);
    final bend =
        origin +
        vm.Vector3(
          math.cos(angle) * spread * 0.55,
          0.7,
          math.sin(angle) * spread * 0.55,
        );
    final end =
        origin +
        vm.Vector3(
          math.cos(angle) * spread,
          1.35 + rng.nextDouble() * 0.35,
          math.sin(angle) * spread,
        );
    branch(origin, bend, 0.085, 0.045);
    branch(bend, end, 0.045, 0.012);
    for (var j = 0; j < 3; j++) {
      final twigAngle = angle + (j - 1) * 0.65;
      final tip =
          end +
          vm.Vector3(
            math.cos(twigAngle) * 0.25,
            j * 0.2,
            math.sin(twigAngle) * 0.25,
          );
      branch(bend, tip, 0.025, 0.006);
      clusters.add(tip);
    }
  }
  clusters.addAll([vm.Vector3(0, 6.8, 0), vm.Vector3(0.35, 6.3, -0.3)]);

  for (final center in clusters) {
    for (var i = 0; i < leavesPerCluster; i++) {
      // Rejection sampling produces full, irregular clusters, not spheres.
      vm.Vector3 offset;
      do {
        offset = vm.Vector3(
          rng.nextDouble() * 2 - 1,
          rng.nextDouble() * 2 - 1,
          rng.nextDouble() * 2 - 1,
        );
      } while (offset.length2 > 1);
      final p =
          center +
          vm.Vector3(offset.x * 0.63, offset.y * 0.73, offset.z * 0.63);
      final normal = vm.Vector3(
        rng.nextDouble() * 2 - 1,
        rng.nextDouble() * 2 - 1,
        rng.nextDouble() * 2 - 1,
      );
      if (normal.length2 < 1e-6) normal.setValues(0, 1, 0);
      normal.normalize();
      final axis = normal.y.abs() > 0.95
          ? vm.Vector3(1, 0, 0)
          : vm.Vector3(0, 1, 0);
      final right = normal.cross(axis).normalized();
      final up = right.cross(normal).normalized();
      final length = 0.13 + rng.nextDouble() * 0.11;
      final width = length * (0.45 + rng.nextDouble() * 0.2);
      // Muted olive, ochre and remaining green for the October start date.
      final tone = rng.nextDouble();
      final color = tone < 0.22
          ? vm.Vector3(0.39, 0.31, 0.13)
          : vm.Vector3(
              0.20 + tone * 0.08,
              0.29 + tone * 0.09,
              0.12 + tone * 0.04,
            );
      final a = p - up * length;
      final b = p + right * width;
      final c = p + up * length;
      final d = p - right * width;
      leaves.triangle(a, b, c, color);
      leaves.triangle(a, c, d, color * 0.9);
    }
  }
  return TreeGeometryData(branches, leaves);
}
