import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../engine/game.dart';
import '../../engine/hud_info.dart';
import '../../player/player_health.dart';
import '../../police/wanted_state.dart';
import 'radar.dart';
import 'radar_math.dart';

/// Плоский компас (вертикальный режим) — вместо круглого радара.
/// Минималистичный, без плашки: стороны света и метки (дом, полиция,
/// добыча) над тонкой линией по направлению от взгляда камеры, по краям —
/// тонкие полосы бронежилета (слева) и здоровья (справа).
class CompassHud extends StatefulWidget {
  const CompassHud({super.key, required this.game, this.height = 28});

  final Game game;
  final double height;

  @override
  State<CompassHud> createState() => _CompassHudState();
}

class _CompassHudState extends State<CompassHud> with SingleTickerProviderStateMixin {
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
      size: Size(double.infinity, widget.height),
      painter: _CompassPainter(widget.game, _time),
    ),
  );
}

class _CompassPainter extends CustomPainter {
  _CompassPainter(this.game, this.time) : super(repaint: time);

  final Game game;
  final ValueNotifier<double> time;
  final List<HudBlip> _blips = [];

  /// Сколько градусов от центра видно до края шкалы.
  static const double _halfFovDegrees = 75;

  static const List<(double, String)> _cardinals = [(0, 'С'), (90, 'В'), (180, 'Ю'), (270, 'З')];

  static const List<Shadow> _shadow = [Shadow(blurRadius: 4, color: Color(0xCC000000))];

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final baseY = h - 3;
    final flash = (time.value * 4).floor().isEven;
    final wanted = wantedState.stars > 0;

    // Края: бронежилет слева, здоровье справа — тонкие линии, растут от
    // компаса наружу.
    final barWidth = size.width * 0.16;
    final health = game.playerHealth;
    final armorFraction = (health.armor / PlayerHealth.maxArmor).clamp(0.0, 1.0);
    final healthFraction = (health.health / PlayerHealth.maxHealth).clamp(0.0, 1.0);
    _line(canvas, 0, barWidth, baseY, armorFraction, HudColors.armor, fromRight: true);
    _line(canvas, size.width - barWidth, size.width, baseY, healthFraction, HudColors.healthColor(healthFraction), fromRight: false);

    final scale = Rect.fromLTRB(barWidth + 14, 0, size.width - barWidth - 14, h);
    // Базовая линия шкалы; при розыске мигает красно-синим.
    canvas.drawLine(
      Offset(scale.left, baseY),
      Offset(scale.right, baseY),
      Paint()
        ..strokeWidth = 1
        ..color = wanted ? (flash ? HudColors.policeRed : HudColors.policeBlue) : Colors.white30,
    );

    canvas.save();
    canvas.clipRect(scale.inflate(2));
    final yaw = game.cameraYaw;
    final cx = scale.center.dx;
    final halfWidth = scale.width / 2;
    double? xOf(double dx, double dz) {
      final angle = viewAngle(dx, dz, yaw) * 180 / math.pi;
      if (angle.abs() > _halfFovDegrees) return null;
      return cx + angle / _halfFovDegrees * halfWidth;
    }

    // Промежуточные стороны — точки, основные — буквы.
    for (var bearing = 45.0; bearing < 360; bearing += 90) {
      final dir = bearingToWorld(bearing);
      final x = xOf(dir.x, dir.z);
      if (x != null) canvas.drawCircle(Offset(x, h * 0.42), 1.3, Paint()..color = Colors.white54);
    }
    for (final (bearing, label) in _cardinals) {
      final dir = bearingToWorld(bearing);
      final x = xOf(dir.x, dir.z);
      if (x == null) continue;
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: label == 'С' ? const Color(0xFFFF7A70) : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            shadows: _shadow,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(x - painter.width / 2, h * 0.42 - painter.height / 2));
    }

    // Метки — точки у базовой линии (дом — домиком).
    final player = game.trackedNode.globalTransform.getTranslation();
    _blips.clear();
    game.collectBlips(_blips);
    for (final blip in _blips) {
      final dx = blip.x - player.x;
      final dz = blip.z - player.z;
      final important = blip.kind == BlipKind.houseForSale || blip.kind == BlipKind.houseOwned || blip.kind == BlipKind.policeCar;
      if (!important && dx * dx + dz * dz > 60 * 60) continue;
      var x = xOf(dx, dz);
      if (x == null) {
        if (!important) continue;
        x = viewAngle(dx, dz, yaw) > 0 ? scale.right : scale.left;
      }
      final at = Offset(x, baseY - 6);
      switch (blip.kind) {
        case BlipKind.houseForSale || BlipKind.houseOwned:
          drawHouseIcon(canvas, at, 4, blip.kind == BlipKind.houseOwned ? HudColors.houseOwned : HudColors.houseForSale);
        case BlipKind.policeCar:
          canvas.drawCircle(at, 2.6, Paint()..color = flash ? HudColors.policeRed : HudColors.policeBlue);
        case BlipKind.officer:
          canvas.drawCircle(at, 2, Paint()..color = HudColors.policeBlue);
        case BlipKind.money:
          canvas.drawCircle(at, 2, Paint()..color = HudColors.money);
        case BlipKind.ammo:
          canvas.drawCircle(at, 2, Paint()..color = HudColors.ammo);
        case BlipKind.armor:
          canvas.drawCircle(at, 2, Paint()..color = HudColors.armor);
      }
    }
    canvas.restore();

    // Куда смотрим — короткая риска по центру.
    canvas.drawLine(
      Offset(cx, baseY - 4),
      Offset(cx, baseY + 3),
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white,
    );
  }

  /// Тонкая полоса брони/здоровья: тусклая дорожка и заливка.
  void _line(Canvas canvas, double left, double right, double y, double fraction, Color color, {required bool fromRight}) {
    final paint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(left + 2, y), Offset(right - 2, y), paint..color = HudColors.track);
    if (fraction <= 0) return;
    final width = (right - left - 4) * fraction;
    final start = fromRight ? right - 2 - width : left + 2;
    canvas.drawLine(Offset(start, y), Offset(start + width, y), paint..color = color);
  }

  @override
  bool shouldRepaint(covariant _CompassPainter old) => old.game != game;
}
