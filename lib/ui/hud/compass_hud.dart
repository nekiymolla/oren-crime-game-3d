import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../engine/game.dart';
import '../../engine/hud_info.dart';
import '../../player/player_health.dart';
import '../../police/wanted_state.dart';
import 'radar.dart';
import 'radar_math.dart';

/// Плоский компас (вертикальный режим) — вместо круглого радара:
/// плашка-пилюля со сторонами света и метками (дом, полиция, добыча) по
/// направлению от взгляда камеры. Рамка — как обод радара: левая
/// половина — бронежилет, правая — здоровье.
class CompassHud extends StatefulWidget {
  const CompassHud({super.key, required this.game, this.height = 38});

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

  static const List<(double, String)> _labels = [
    (0, 'С'),
    (45, 'СВ'),
    (90, 'В'),
    (135, 'ЮВ'),
    (180, 'Ю'),
    (225, 'ЮЗ'),
    (270, 'З'),
    (315, 'СЗ'),
  ];

  static const double _borderWidth = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final rect = (Offset.zero & size).deflate(_borderWidth / 2);
    final radius = rect.height / 2;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)), Paint()..color = HudColors.frame);

    // Рамка — как обод радара: левая половина — бронежилет, правая —
    // здоровье; заполняются от середины низа по краю к середине верха.
    final health = game.playerHealth;
    final armorFraction = (health.armor / PlayerHealth.maxArmor).clamp(0.0, 1.0);
    final healthFraction = (health.health / PlayerHealth.maxHealth).clamp(0.0, 1.0);
    _halfBorder(canvas, rect, radius, left: true, fraction: armorFraction, color: HudColors.armor);
    _halfBorder(canvas, rect, radius, left: false, fraction: healthFraction, color: HudColors.healthColor(healthFraction));

    // Шкала во всю ширину плашки.
    final scale = Rect.fromLTRB(rect.left + radius, 0, rect.right - radius, h);
    canvas.save();
    canvas.clipRect(scale);
    final yaw = game.cameraYaw;
    final cx = scale.center.dx;
    final halfWidth = scale.width / 2;
    double? xOf(double dx, double dz) {
      final angle = viewAngle(dx, dz, yaw) * 180 / math.pi;
      if (angle.abs() > _halfFovDegrees) return null;
      return cx + angle / _halfFovDegrees * halfWidth;
    }

    final tick = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.2;
    for (var bearing = 0.0; bearing < 360; bearing += 15) {
      if (bearing % 45 == 0) continue;
      final dir = bearingToWorld(bearing);
      final x = xOf(dir.x, dir.z);
      if (x != null) canvas.drawLine(Offset(x, h * 0.62), Offset(x, h * 0.78), tick);
    }
    for (final (bearing, label) in _labels) {
      final dir = bearingToWorld(bearing);
      final x = xOf(dir.x, dir.z);
      if (x == null) continue;
      final cardinal = label.length == 1;
      drawCenteredText(
        canvas,
        label,
        Offset(x, h * 0.5),
        cardinal ? 14 : 11,
        label == 'С' ? HudColors.policeRed : (cardinal ? Colors.white : Colors.white70),
        bold: cardinal,
      );
    }

    // Метки.
    final flash = (time.value * 4).floor().isEven;
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
        x = viewAngle(dx, dz, yaw) > 0 ? scale.right - 6 : scale.left + 6;
      }
      final at = Offset(x, h * 0.22 + 2);
      switch (blip.kind) {
        case BlipKind.houseForSale || BlipKind.houseOwned:
          drawHouseIcon(canvas, at + const Offset(0, 1), 5, blip.kind == BlipKind.houseOwned ? HudColors.houseOwned : HudColors.houseForSale);
        case BlipKind.policeCar:
          canvas.drawCircle(at, 3.5, Paint()..color = flash ? HudColors.policeRed : HudColors.policeBlue);
        case BlipKind.officer:
          canvas.drawCircle(at, 2.5, Paint()..color = HudColors.policeBlue);
        case BlipKind.money:
          canvas.drawCircle(at, 2.5, Paint()..color = HudColors.money);
        case BlipKind.ammo:
          canvas.drawCircle(at, 2.5, Paint()..color = HudColors.ammo);
        case BlipKind.armor:
          canvas.drawCircle(at, 2.5, Paint()..color = HudColors.armor);
      }
    }
    canvas.restore();

    // Центральная риска — куда смотрим; при розыске мигает красно-синим
    // (рамка занята бронёй и здоровьем).
    final wanted = wantedState.stars > 0;
    final marker = Path()
      ..moveTo(cx - 5, rect.bottom)
      ..lineTo(cx + 5, rect.bottom)
      ..lineTo(cx, rect.bottom - 6)
      ..close();
    canvas.drawPath(marker, Paint()..color = wanted ? (flash ? HudColors.policeRed : HudColors.policeBlue) : Colors.white);
  }

  /// Половина рамки-пилюли от середины низа через закруглённый край к
  /// середине верха: тусклая дорожка и заливка на [fraction] длины.
  void _halfBorder(Canvas canvas, Rect rect, double radius, {required bool left, required double fraction, required Color color}) {
    final cx = rect.center.dx;
    final path = Path()..moveTo(cx, rect.bottom);
    if (left) {
      path
        ..lineTo(rect.left + radius, rect.bottom)
        ..arcTo(Rect.fromCircle(center: Offset(rect.left + radius, rect.center.dy), radius: radius), math.pi / 2, math.pi, false)
        ..lineTo(cx, rect.top);
    } else {
      path
        ..lineTo(rect.right - radius, rect.bottom)
        ..arcTo(Rect.fromCircle(center: Offset(rect.right - radius, rect.center.dy), radius: radius), math.pi / 2, -math.pi, false)
        ..lineTo(cx, rect.top);
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _borderWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint..color = HudColors.track);
    if (fraction <= 0) return;
    final metric = path.computeMetrics().first;
    canvas.drawPath(metric.extractPath(0, metric.length * fraction), paint..color = color);
  }

  @override
  bool shouldRepaint(covariant _CompassPainter old) => old.game != game;
}
