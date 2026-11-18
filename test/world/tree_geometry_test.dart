import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:crime_oren/world/tree_geometry.dart';
import 'package:crime_oren/world/vegetation.dart' show treeCanopyRadius;

void main() {
  test('tree has valid finite triangles inside its planting clearance', () {
    final tree = buildDeciduousTree();
    var height = 0.0;
    for (final mesh in [tree.branches, tree.leaves]) {
      expect(mesh.positions.length % 9, 0);
      expect(mesh.normals.length, mesh.positions.length);
      expect(mesh.colors.length, mesh.positions.length ~/ 3 * 4);
      for (var i = 0; i < mesh.positions.length; i += 3) {
        final x = mesh.positions[i];
        final y = mesh.positions[i + 1];
        final z = mesh.positions[i + 2];
        expect(x.isFinite && y.isFinite && z.isFinite, isTrue);
        expect(y, greaterThanOrEqualTo(-0.01));
        expect(math.sqrt(x * x + z * z), lessThanOrEqualTo(treeCanopyRadius));
        height = math.max(height, y);
        final normalLength = math.sqrt(
          mesh.normals[i] * mesh.normals[i] +
              mesh.normals[i + 1] * mesh.normals[i + 1] +
              mesh.normals[i + 2] * mesh.normals[i + 2],
        );
        expect(normalLength, closeTo(1, 1e-5));
      }
    }
    expect(height, inInclusiveRange(7.0, 9.0));
    expect(
      tree.branches.triangleCount + tree.leaves.triangleCount,
      lessThan(4000),
    );
  });

  test('tree generation is reproducible across launches', () {
    final a = buildDeciduousTree();
    final b = buildDeciduousTree();
    expect(a.leaves.positions, b.leaves.positions);
    expect(a.branches.colors, b.branches.colors);
    expect(
      buildDeciduousTree(seed: 74).leaves.positions,
      isNot(a.leaves.positions),
    );
  });
}
