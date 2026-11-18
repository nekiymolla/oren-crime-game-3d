import 'dart:math' as math;
import 'dart:typed_data';
import 'package:vector_math/vector_math.dart' as vm;
import 'nav_grid.dart';

class CitySurface {
  CitySurface(this.outline);
  final List<vm.Vector2> outline;
  bool contains(double x, double z) {
    var inside = false;
    for (var i = 0, j = outline.length - 1; i < outline.length; j = i++) {
      final a = outline[i], b = outline[j];
      if ((a.y > z) != (b.y > z) &&
          x < (b.x - a.x) * (z - a.y) / (b.y - a.y) + a.x) {
        inside = !inside;
      }
    }
    return inside;
  }
}

/// The OSM import omitted some untyped pitches. Protect these confirmed
/// footprints from authored hills and random planting without covering roads
/// or houses. The same patched grid drives terrain, trees and pedestrians.
NavGrid protectCitySurfaces(NavGrid source, List<CitySurface> surfaces) {
  final nav = NavGrid(
    minX: source.minX,
    minZ: source.minZ,
    metersPerCell: source.metersPerCell,
    width: source.width,
    height: source.height,
    cells: Uint8List.fromList(source.cells),
  );
  for (final surface in surfaces) {
    if (surface.outline.length < 3) continue;
    final xs = surface.outline.map((p) => p.x),
        zs = surface.outline.map((p) => p.y),
        cell = nav.metersPerCell;
    final x0 = math.max(0, ((xs.reduce(math.min) - nav.minX) / cell).floor());
    final x1 = math.min(
      nav.width - 1,
      ((xs.reduce(math.max) - nav.minX) / cell).ceil(),
    );
    final z0 = math.max(0, ((zs.reduce(math.min) - nav.minZ) / cell).floor());
    final z1 = math.min(
      nav.height - 1,
      ((zs.reduce(math.max) - nav.minZ) / cell).ceil(),
    );
    for (var z = z0; z <= z1; z++) {
      for (var x = x0; x <= x1; x++) {
        final index = z * nav.width + x;
        if (nav.cells[index] == NavKind.ground.index &&
            surface.contains(
              nav.minX + (x + .5) * cell,
              nav.minZ + (z + .5) * cell,
            )) {
          nav.cells[index] = NavKind.sidewalk.index;
        }
      }
    }
  }
  return nav;
}
