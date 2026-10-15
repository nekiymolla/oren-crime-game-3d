import 'dart:math' as math;

import 'package:crime_oren/ui/hud/radar_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Камера смотрит вдоль +Z (yaw 0): вперёд +Z, вправо +X (как
  // FollowCameraController.right = up × forward).
  test('вперёд по взгляду камеры — вверх по радару, вправо — вправо', () {
    final ahead = worldToRadar(0, 10, 0, pixelsPerMeter: 1, centerX: 50, centerY: 50);
    expect(ahead.x, closeTo(50, 1e-9));
    expect(ahead.y, closeTo(40, 1e-9));
    final right = worldToRadar(10, 0, 0, pixelsPerMeter: 1, centerX: 50, centerY: 50);
    expect(right.x, closeTo(60, 1e-9));

    // Повернулись (yaw = 90°: вперёд +X) — то, что было справа, теперь впереди.
    final turned = worldToRadar(10, 0, math.pi / 2, pixelsPerMeter: 1, centerX: 50, centerY: 50);
    expect(turned.x, closeTo(50, 1e-9));
    expect(turned.y, closeTo(40, 1e-9));
  });

  test('угол на компасе: впереди 0, справа +90°, слева −90°', () {
    expect(viewAngle(0, 5, 0), closeTo(0, 1e-9));
    expect(viewAngle(5, 0, 0), closeTo(math.pi / 2, 1e-9));
    expect(viewAngle(-5, 0, 0), closeTo(-math.pi / 2, 1e-9));
  });

  test('азимуты в координатах игры: север +Z, восток +X', () {
    final north = bearingToWorld(0);
    expect(north.x, closeTo(0, 1e-9));
    expect(north.z, closeTo(1, 1e-9));
    final east = bearingToWorld(90);
    expect(east.x, closeTo(1, 1e-9));
    expect(east.z, closeTo(0, 1e-9));
  });

  test('картинка карты ложится так же, как точки радара', () {
    const map = MinimapInfo(minX: -800, minZ: -800, metersPerPixel: 2);
    for (final yaw in [0.0, 0.7, 2.5, -1.9]) {
      final t = mapImageTransform(
        map: map,
        playerX: 13,
        playerZ: -27,
        yaw: yaw,
        pixelsPerMeter: 0.8,
        centerX: 60,
        centerY: 60,
      );
      // Пиксель карты, соответствующий мировой точке (40, 5).
      const u = (40 - -800) / 2;
      const v = (5 - -800) / 2;
      final viaImage = (x: t.a * u + t.c * v + t.tx, y: t.b * u + t.d * v + t.ty);
      final direct = worldToRadar(40 - 13, 5 - -27, yaw, pixelsPerMeter: 0.8, centerX: 60, centerY: 60);
      expect(viaImage.x, closeTo(direct.x, 1e-6), reason: 'yaw $yaw');
      expect(viaImage.y, closeTo(direct.y, 1e-6), reason: 'yaw $yaw');
    }
  });

  test('радар отдаляется на скорости, но не бесконечно', () {
    expect(radarRangeMeters(0), 60);
    expect(radarRangeMeters(20), greaterThan(radarRangeMeters(5)));
    expect(radarRangeMeters(500), 150);
  });
}
