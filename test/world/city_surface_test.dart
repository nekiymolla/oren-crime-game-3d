import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:crime_oren/world/city_surface.dart';
import 'package:crime_oren/world/nav_grid.dart';

void main() {
  test(
    'asset byte views stay immutable while the overlay gets its own cells',
    () {
      final source = NavGrid(
        minX: 0,
        minZ: 0,
        metersPerCell: 1,
        width: 2,
        height: 2,
        cells: Uint8List(4).asUnmodifiableView(),
      );
      final patched = protectCitySurfaces(source, [
        CitySurface([
          vm.Vector2(-1, -1),
          vm.Vector2(3, -1),
          vm.Vector2(3, 3),
          vm.Vector2(-1, 3),
        ]),
      ]);
      expect(source.cells.every((k) => k == 0), true);
      expect(patched.cells.every((k) => k == NavKind.sidewalk.index), true);
    },
  );
  final polygon = CitySurface([
    vm.Vector2(1, 1),
    vm.Vector2(6, 1),
    vm.Vector2(6, 6),
    vm.Vector2(1, 6),
  ]);
  test(
    'surface mask keeps asphalt and buildings while protecting bare ground',
    () {
      final nav = NavGrid(
        minX: 0,
        minZ: 0,
        metersPerCell: 1,
        width: 8,
        height: 8,
        cells: Uint8List(64),
      );
      nav.cells[2 * 8 + 2] = NavKind.building.index;
      nav.cells[3 * 8 + 2] = NavKind.majorRoad.index;
      final patched = protectCitySurfaces(nav, [polygon]);
      expect(patched.kindAt(4.5, 4.5), NavKind.sidewalk);
      expect(patched.kindAt(2.5, 2.5), NavKind.building);
      expect(patched.kindAt(2.5, 3.5), NavKind.majorRoad);
      expect(patched.kindAt(7.5, 4.5), NavKind.ground);
    },
  );
  test('surface mask clips polygons extending outside the navigation grid', () {
    final nav = NavGrid(
      minX: 0,
      minZ: 0,
      metersPerCell: 1,
      width: 2,
      height: 2,
      cells: Uint8List(4),
    );
    final patched = protectCitySurfaces(nav, [
      CitySurface([
        vm.Vector2(-5, -5),
        vm.Vector2(5, -5),
        vm.Vector2(5, 5),
        vm.Vector2(-5, 5),
      ]),
    ]);
    expect(patched.cells.every((k) => k == NavKind.sidewalk.index), true);
  });
}
