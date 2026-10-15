import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../engine/game.dart';
import '../../engine/hud_info.dart';
import '../../player/player_health.dart';
import '../../police/wanted_state.dart';
import 'radar_math.dart';

/// Цвета HUD — в духе GTA IV, но светлее и теплее.
abstract final class HudColors {
  static const Color health = Color(0xFF5BE37D);
  static const Color healthLow = Color(0xFFFFC145);
  static const Color healthCritical = Color(0xFFFF5A52);
  static const Color armor = Color(0xFF54A8FF);
  static const Color track = Color(0x33FFFFFF);
  static const Color frame = Color(0xCC14181F);
  static const Color houseForSale = Color(0xFF5BE37D);
  static const Color houseOwned = Color(0xFF54A8FF);
  static const Color policeRed = Color(0xFFFF4A4A);
  static const Color policeBlue = Color(0xFF4A8BFF);
  static const Color money = Color(0xFF7CFC9A);
  static const Color ammo = Color(0xFFFFC145);
  static const Color mapGround = Color(0xFF5C7654);

  static Color healthColor(double fraction) =>
      fraction > 0.5 ? health : (fraction > 0.25 ? healthLow : healthCritical);
}

/// Круглый радар (горизонтальный режим): карта района, повёрнутая по
/// взгляду камеры, метки, стрелка игрока. Обод — слева бронежилет, справа
/// здоровье: дуги заполняются снизу вверх.
class RadarHud extends StatefulWidget {
  const RadarHud({super.key, required this.game, required this.minimap, this.size = 150});

  final Game game;
  final Minimap? minimap;
  final double size;

  @override
  State<RadarHud> createState() => _RadarHudState();
}

class _RadarHudState extends State<RadarHud> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _time = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) => _time.value = elapsed.inMicroseconds / 1e6)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(
      size: Size.square(widget.size),
      painter: _RadarPainter(widget.game, widget.minimap, _time),
    ),
  );
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.game, this.minimap, this.time) : super(repaint: time);

  final Game game;
  final Minimap? minimap;
  final ValueNotifier<double> time;
  final List<HudBlip> _blips = [];

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.width / 2;
    const arcWidth = 7.0;
    final arcRadius = outer - arcWidth / 2;
    final mapRadius = arcRadius - arcWidth / 2 - 4;

    final player = game.trackedNode.globalTransform.getTranslation();
    final yaw = game.cameraYaw;
    final pixelsPerMeter = mapRadius / radarRangeMeters(game.playerSpeed);

    // Подложка и рамка.
    canvas.drawCircle(center, outer, Paint()..color = HudColors.frame);

    // Карта района в круге.
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: mapRadius)));
    canvas.drawCircle(center, mapRadius, Paint()..color = HudColors.mapGround);
    final map = minimap;
    if (map != null) {
      final t = mapImageTransform(
        map: map.info,
        playerX: player.x,
        playerZ: player.z,
        yaw: yaw,
        pixelsPerMeter: pixelsPerMeter,
        centerX: center.dx,
        centerY: center.dy,
      );
      canvas.save();
      canvas.transform(Float64List.fromList([t.a, t.b, 0, 0, t.c, t.d, 0, 0, 0, 0, 1, 0, t.tx, t.ty, 0, 1]));
      canvas.drawImage(map.image, Offset.zero, Paint()..filterQuality = FilterQuality.low);
      canvas.restore();
    }

    // Метки: дом и полиция прижимаются к краю, если далеко, остальное —
    // только в пределах радара.
    _blips.clear();
    game.collectBlips(_blips);
    final flash = (time.value * 4).floor().isEven;
    for (final blip in _blips) {
      final p = worldToRadar(
        blip.x - player.x,
        blip.z - player.z,
        yaw,
        pixelsPerMeter: pixelsPerMeter,
        centerX: center.dx,
        centerY: center.dy,
      );
      var offset = Offset(p.x, p.y);
      final fromCenter = offset - center;
      final clampToEdge = blip.kind == BlipKind.houseForSale || blip.kind == BlipKind.houseOwned || blip.kind == BlipKind.policeCar;
      if (fromCenter.distance > mapRadius - 6) {
        if (!clampToEdge) continue;
        offset = center + fromCenter / fromCenter.distance * (mapRadius - 6);
      }
      _drawBlip(canvas, blip.kind, offset, flash);
    }

    // Игрок — стрелка по его курсу относительно взгляда камеры.
    final heading = game.playerHeading;
    final view = worldToView(math.sin(heading), math.cos(heading), yaw);
    final angle = math.atan2(view.x, view.y);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final arrow = Path()
      ..moveTo(0, -8)
      ..lineTo(6, 6)
      ..lineTo(0, 3)
      ..lineTo(-6, 6)
      ..close();
    canvas.drawPath(arrow, Paint()..color = Colors.black54..style = PaintingStyle.stroke..strokeWidth = 3);
    canvas.drawPath(arrow, Paint()..color = Colors.white);
    canvas.restore();
    canvas.restore(); // clip

    // Розыск — обод карты мигает красно-синим.
    final wanted = wantedState.stars > 0;
    canvas.drawCircle(
      center,
      mapRadius + 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = wanted ? (flash ? HudColors.policeRed : HudColors.policeBlue) : Colors.white24,
    );

    // Север — буква на ободе карты.
    final north = bearingToWorld(0);
    final n = worldToView(north.x, north.z, yaw);
    final nLength = math.sqrt(n.x * n.x + n.y * n.y);
    final nPos = center + Offset(n.x / nLength, -n.y / nLength) * (mapRadius - 1);
    canvas.drawCircle(nPos, 7.5, Paint()..color = HudColors.frame);
    _text(canvas, 'С', nPos, 10, Colors.white, bold: true);

    // Дуги: слева бронежилет, справа здоровье; заполняются снизу вверх.
    const gap = 0.12; // зазор сверху и снизу, рад
    const half = math.pi - 2 * gap;
    final arcRect = Rect.fromCircle(center: center, radius: arcRadius);
    Paint arcPaint(Color color) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = arcWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    final health = game.playerHealth;
    final armorFraction = (health.armor / PlayerHealth.maxArmor).clamp(0.0, 1.0);
    final healthFraction = (health.health / PlayerHealth.maxHealth).clamp(0.0, 1.0);
    canvas.drawArc(arcRect, math.pi / 2 + gap, half, false, arcPaint(HudColors.track));
    canvas.drawArc(arcRect, math.pi / 2 - gap, -half, false, arcPaint(HudColors.track));
    if (armorFraction > 0) {
      canvas.drawArc(arcRect, math.pi / 2 + gap, half * armorFraction, false, arcPaint(HudColors.armor));
    }
    if (healthFraction > 0) {
      canvas.drawArc(arcRect, math.pi / 2 - gap, -half * healthFraction, false, arcPaint(HudColors.healthColor(healthFraction)));
    }
  }

  void _drawBlip(Canvas canvas, BlipKind kind, Offset at, bool flash) {
    switch (kind) {
      case BlipKind.houseForSale || BlipKind.houseOwned:
        final color = kind == BlipKind.houseOwned ? HudColors.houseOwned : HudColors.houseForSale;
        drawHouseIcon(canvas, at, 7, color);
      case BlipKind.policeCar:
        canvas.drawCircle(at, 5, Paint()..color = Colors.black54);
        canvas.drawCircle(at, 4, Paint()..color = flash ? HudColors.policeRed : HudColors.policeBlue);
      case BlipKind.officer:
        canvas.drawCircle(at, 3.5, Paint()..color = Colors.black54);
        canvas.drawCircle(at, 2.6, Paint()..color = HudColors.policeBlue);
      case BlipKind.money:
        canvas.drawCircle(at, 3, Paint()..color = HudColors.money);
      case BlipKind.ammo:
        canvas.drawCircle(at, 3, Paint()..color = HudColors.ammo);
      case BlipKind.armor:
        canvas.drawCircle(at, 3, Paint()..color = HudColors.armor);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => old.game != game || old.minimap != minimap;
}

/// Значок домика: квадрат с крышей, с тёмной обводкой.
void drawHouseIcon(Canvas canvas, Offset at, double size, Color color) {
  final path = Path()
    ..moveTo(at.dx, at.dy - size)
    ..lineTo(at.dx + size, at.dy - size * 0.1)
    ..lineTo(at.dx + size * 0.7, at.dy - size * 0.1)
    ..lineTo(at.dx + size * 0.7, at.dy + size * 0.8)
    ..lineTo(at.dx - size * 0.7, at.dy + size * 0.8)
    ..lineTo(at.dx - size * 0.7, at.dy - size * 0.1)
    ..lineTo(at.dx - size, at.dy - size * 0.1)
    ..close();
  canvas.drawPath(path, Paint()..color = Colors.black87..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeJoin = StrokeJoin.round);
  canvas.drawPath(path, Paint()..color = color);
}

void _text(Canvas canvas, String text, Offset center, double size, Color color, {bool bold = false}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, height: 1.0),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
}

/// Общий для компаса текст по центру точки.
void drawCenteredText(Canvas canvas, String text, Offset center, double size, Color color, {bool bold = false}) =>
    _text(canvas, text, center, size, color, bold: bold);
