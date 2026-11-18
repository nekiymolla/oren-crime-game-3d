import 'nav_grid.dart';

/// Conservative canopy footprint against the complete map, including chunks
/// not loaded yet. Tests cell squares rather than five sparse ray samples.
bool isTreeGroundClear(NavGrid nav, double x, double z, double radius) {
  if (!radius.isFinite || radius < 0 || !x.isFinite || !z.isFinite) {
    return false;
  }
  final cell = nav.metersPerCell;
  final minX = ((x - radius - nav.minX) / cell).floor();
  final maxX = ((x + radius - nav.minX) / cell).floor();
  final minZ = ((z - radius - nav.minZ) / cell).floor();
  final maxZ = ((z + radius - nav.minZ) / cell).floor();
  if (minX < 0 || minZ < 0 || maxX >= nav.width || maxZ >= nav.height) {
    return false;
  }
  for (var iz = minZ; iz <= maxZ; iz++) {
    for (var ix = minX; ix <= maxX; ix++) {
      final left = nav.minX + ix * cell, top = nav.minZ + iz * cell;
      final dx = x - x.clamp(left, left + cell);
      final dz = z - z.clamp(top, top + cell);
      if (dx * dx + dz * dz > radius * radius) continue;
      if (nav.kindAt(left + cell * .5, top + cell * .5) != NavKind.ground) {
        return false;
      }
    }
  }
  return true;
}
