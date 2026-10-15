import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

/// Математика радара и компаса — чистые функции, проверены тестами.
///
/// Всё строится от тех же векторов камеры, что и картинка на экране
/// (FollowCameraController): вперёд (sin yaw, cos yaw), вправо
/// (cos yaw, −sin yaw) — так что справа на радаре ровно то, что справа на
/// экране. Движок левосторонний, поэтому "географически" выведенные оси
/// тут не годятся.

/// Смещение (dx, dz) в системе взгляда камеры: x — вправо, y — вперёд.
({double x, double y}) worldToView(double dx, double dz, double yaw) {
  final c = math.cos(yaw);
  final s = math.sin(yaw);
  return (x: dx * c - dz * s, y: dx * s + dz * c);
}

/// Угол направления (dx, dz) от взгляда камеры, рад: 0 — прямо,
/// положительный — вправо. Для компаса.
double viewAngle(double dx, double dz, double yaw) {
  final v = worldToView(dx, dz, yaw);
  return math.atan2(v.x, v.y);
}

/// Мировое направление по компасному азимуту [bearingDegrees] (0 — север,
/// 90 — восток). В координатах игры север — +Z, восток — +X
/// (tools/osm_pipeline/calibration.json; в glTF север был −Z, движок
/// переворачивает Z при загрузке).
({double x, double z}) bearingToWorld(double bearingDegrees) {
  final b = bearingDegrees * math.pi / 180;
  return (x: math.sin(b), z: math.cos(b));
}

/// Сколько метров от игрока до края радара: на скорости карта
/// отдаляется, как в GTA.
double radarRangeMeters(double speed) => math.min(150.0, 60.0 + speed * 2.5);

/// Аффинное преобразование картинки карты на экран радара: пиксель
/// (u, v) картинки -> экран. Возвращает (a, b, c, d, tx, ty):
/// x' = a*u + c*v + tx, y' = b*u + d*v + ty.
({double a, double b, double c, double d, double tx, double ty}) mapImageTransform({
  required MinimapInfo map,
  required double playerX,
  required double playerZ,
  required double yaw,
  required double pixelsPerMeter,
  required double centerX,
  required double centerY,
}) {
  final cs = math.cos(yaw);
  final sn = math.sin(yaw);
  final k = pixelsPerMeter;
  final m = map.metersPerPixel;
  final ox = map.minX - playerX;
  final oz = map.minZ - playerZ;
  return (
    a: k * m * cs,
    b: -k * m * sn,
    c: -k * m * sn,
    d: -k * m * cs,
    tx: centerX + k * (cs * ox - sn * oz),
    ty: centerY - k * (sn * ox + cs * oz),
  );
}

/// Точка мира на экране радара (центр — игрок).
({double x, double y}) worldToRadar(
  double dx,
  double dz,
  double yaw, {
  required double pixelsPerMeter,
  required double centerX,
  required double centerY,
}) {
  final v = worldToView(dx, dz, yaw);
  return (x: centerX + v.x * pixelsPerMeter, y: centerY - v.y * pixelsPerMeter);
}

/// Привязка карты района к миру — assets/data/minimap.json
/// (tools/osm_pipeline/render_minimap.mjs).
class MinimapInfo {
  const MinimapInfo({required this.minX, required this.minZ, required this.metersPerPixel});

  factory MinimapInfo.fromJson(Map<String, dynamic> json) => MinimapInfo(
    minX: (json['minX'] as num).toDouble(),
    minZ: (json['minZ'] as num).toDouble(),
    metersPerPixel: (json['metersPerPixel'] as num).toDouble(),
  );

  final double minX;
  final double minZ;
  final double metersPerPixel;
}

/// Карта района: картинка и привязка.
class Minimap {
  const Minimap(this.image, this.info);

  final ui.Image image;
  final MinimapInfo info;

  static Future<Minimap> load() async {
    final json = jsonDecode(await rootBundle.loadString('assets/data/minimap.json')) as Map<String, dynamic>;
    final bytes = await rootBundle.load('assets/data/${json['image']}');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    return Minimap(frame.image, MinimapInfo.fromJson(json));
  }
}
