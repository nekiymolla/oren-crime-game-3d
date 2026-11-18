import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:crime_oren/world/nav_grid.dart';
import 'package:crime_oren/world/tree_placement.dart';

void main() {
  late NavGrid nav;
  setUp(
    () => nav = NavGrid(
      minX: 0,
      minZ: 0,
      metersPerCell: 1,
      width: 40,
      height: 40,
      cells: Uint8List(1600),
    ),
  );
  test('open ground allows a canopy, edges and paved cells do not', () {
    expect(isTreeGroundClear(nav, 15, 15, 3.1), isTrue);
    expect(isTreeGroundClear(nav, 1, 1, 3.1), isFalse);
    nav.cells[15 * 40 + 16] = NavKind.minorRoad.index;
    expect(isTreeGroundClear(nav, 15, 15, 3.1), isFalse);
  });
  test(
    'diagonal house corner inside a canopy cannot slip between five rays',
    () {
      nav.cells[17 * 40 + 17] = NavKind.building.index;
      expect(isTreeGroundClear(nav, 15, 15, 3.1), isFalse);
      expect(isTreeGroundClear(nav, 15, 15, 2.5), isTrue);
    },
  );
  test('a narrow walkway and invalid inputs are rejected', () {
    nav.cells[15 * 40 + 18] = NavKind.sidewalk.index;
    expect(isTreeGroundClear(nav, 15, 15, 3.1), isFalse);
    expect(isTreeGroundClear(nav, double.nan, 15, 3), isFalse);
    expect(isTreeGroundClear(nav, 15, 15, -1), isFalse);
  });
}
