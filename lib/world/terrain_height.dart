import 'dart:math' as math;
import 'dart:typed_data';

import 'package:vector_math/vector_math.dart' as vm;

import 'nav_grid.dart';

/// Authored urban relief, not surveyed elevations. Streets, paths and house
/// footprints retain their OSM datum; only unoccupied ground can rise.
/// Both rendering and physics sample the same 4 m triangulated height field.
class TerrainHeight {
  TerrainHeight(NavGrid nav)
    : minX = (nav.minX / spacing).floor() * spacing,
      minZ = (nav.minZ / spacing).floor() * spacing,
      width = (nav.width * nav.metersPerCell / spacing).ceil() + 2,
      depth = (nav.height * nav.metersPerCell / spacing).ceil() + 2 {
    final distances = Float32List(width * depth);
    for (var z = 0; z < depth; z++) {
      for (var x = 0; x < width; x++) {
        final wx = minX + x * spacing, wz = minZ + z * spacing;
        var clear = true;
        // Conservative apron also keeps coarse triangles off narrow paths.
        for (var dz = -6; dz <= 6 && clear; dz++) {
          for (var dx = -6; dx <= 6; dx++) {
            if (nav.kindAt(wx + dx, wz + dz) != NavKind.ground) {
              clear = false;
              break;
            }
          }
        }
        distances[z * width + x] = clear ? 1000 : 0;
      }
    }
    void relax(int x, int z, int dx, int dz, double cost) {
      final nx = x + dx, nz = z + dz;
      if (nx < 0 || nz < 0 || nx >= width || nz >= depth) return;
      final i = z * width + x;
      distances[i] = math.min(distances[i], distances[nz * width + nx] + cost);
    }

    for (var z = 0; z < depth; z++) {
      for (var x = 0; x < width; x++) {
        relax(x, z, -1, 0, spacing);
        relax(x, z, 0, -1, spacing);
        relax(x, z, -1, -1, spacing * math.sqrt2);
        relax(x, z, 1, -1, spacing * math.sqrt2);
      }
    }
    for (var z = depth - 1; z >= 0; z--) {
      for (var x = width - 1; x >= 0; x--) {
        relax(x, z, 1, 0, spacing);
        relax(x, z, 0, 1, spacing);
        relax(x, z, 1, 1, spacing * math.sqrt2);
        relax(x, z, -1, 1, spacing * math.sqrt2);
      }
    }
    _heights = Float32List(width * depth);
    for (var z = 0; z < depth; z++) {
      for (var x = 0; x < width; x++) {
        final wx = minX + x * spacing, wz = minZ + z * spacing;
        final t = (distances[z * width + x] / 30).clamp(0.0, 1.0);
        final apron = t * t * (3 - 2 * t);
        // Broad ridges and shallow hollows, with no alpine-looking peaks.
        final relief =
            2.5 +
            1.15 * math.sin(wx / 91 + wz / 137) +
            0.75 * math.cos(wz / 63 - wx / 173);
        _heights[z * width + x] = relief * apron;
      }
    }
  }

  static const double spacing = 4;
  final double minX, minZ;
  final int width, depth;
  late final Float32List _heights;

  double _at(int x, int z) =>
      x < 0 || z < 0 || x >= width || z >= depth ? 0 : _heights[z * width + x];

  double heightAt(double x, double z) {
    final gx = (x - minX) / spacing, gz = (z - minZ) / spacing;
    final ix = gx.floor(), iz = gz.floor();
    final u = gx - ix, v = gz - iz;
    final a = _at(ix, iz), b = _at(ix + 1, iz);
    final c = _at(ix, iz + 1), d = _at(ix + 1, iz + 1);
    return u + v <= 1
        ? a + (b - a) * u + (c - a) * v
        : d + (c - d) * (1 - u) + (b - d) * (1 - v);
  }

  vm.Vector3 normalAt(double x, double z) {
    const e = 0.1;
    return vm.Vector3(
      heightAt(x - e, z) - heightAt(x + e, z),
      2 * e,
      heightAt(x, z - e) - heightAt(x, z + e),
    ).normalized();
  }

  /// Short camera-arm cast. Terrain never enters the expensive scene raycast.
  double? cast(vm.Vector3 origin, vm.Vector3 direction, double reach) {
    for (var t = 0.0; t <= reach; t += 0.15) {
      final p = origin + direction * t;
      if (p.y <= heightAt(p.x, p.z) + 0.12) return math.max(0, t - 0.15);
    }
    final p = origin + direction * reach;
    return p.y <= heightAt(p.x, p.z) + 0.12 ? math.max(0, reach - 0.15) : null;
  }
}
