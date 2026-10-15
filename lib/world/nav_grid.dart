import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// Что лежит в клетке навигационной сетки (tools/osm_pipeline/
/// render_minimap.mjs, assets/data/nav_grid.bin).
enum NavKind { ground, majorRoad, minorRoad, sidewalk, building }

/// Навигационная сетка района, 1 м на клетку, в координатах игры: по ней
/// пешеходы бродят, не заходя в дома и на крупные дороги, а полосы
/// трафика проверяются на "только асфальт". Чистая логика — тестируется
/// с подставной сеткой.
class NavGrid {
  NavGrid({
    required this.minX,
    required this.minZ,
    required this.metersPerCell,
    required this.width,
    required this.height,
    required this.cells,
  });

  final double minX;
  final double minZ;
  final double metersPerCell;
  final int width;
  final int height;
  final Uint8List cells;

  /// Вне сетки — как дом: туда нельзя ни пешком, ни на машине.
  NavKind kindAt(double x, double z) {
    final cx = ((x - minX) / metersPerCell).floor();
    final cz = ((z - minZ) / metersPerCell).floor();
    if (cx < 0 || cz < 0 || cx >= width || cz >= height) return NavKind.building;
    final k = cells[cz * width + cx];
    return k < NavKind.values.length ? NavKind.values[k] : NavKind.building;
  }

  /// Пешком: земля, тротуар и мелкие дороги (их можно переходить).
  bool isWalkable(double x, double z) {
    final k = kindAt(x, z);
    return k == NavKind.ground || k == NavKind.sidewalk || k == NavKind.minorRoad;
  }

  /// На машине: только асфальт.
  bool isDrivable(double x, double z) {
    final k = kindAt(x, z);
    return k == NavKind.majorRoad || k == NavKind.minorRoad;
  }

  bool isBuilding(double x, double z) => kindAt(x, z) == NavKind.building;

  /// Доля точек на отрезке (через [step] м), где [test] ложно.
  double badFraction(double ax, double az, double bx, double bz, bool Function(double x, double z) test, {double step = 1.0}) {
    final dx = bx - ax;
    final dz = bz - az;
    final length = (dx * dx + dz * dz);
    final steps = (length <= 0 ? 0 : (math.sqrt(length) / step).ceil()).clamp(1, 100000);
    var bad = 0;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      if (!test(ax + dx * t, az + dz * t)) bad++;
    }
    return bad / (steps + 1);
  }

  static Future<NavGrid> load() async {
    final meta = jsonDecode(await rootBundle.loadString('assets/data/minimap.json')) as Map<String, dynamic>;
    final nav = meta['nav'] as Map<String, dynamic>;
    final bytes = await rootBundle.load('assets/data/${nav['file']}');
    return NavGrid(
      minX: (meta['minX'] as num).toDouble(),
      minZ: (meta['minZ'] as num).toDouble(),
      metersPerCell: (nav['metersPerCell'] as num).toDouble(),
      width: nav['width'] as int,
      height: nav['height'] as int,
      cells: bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  }
}
