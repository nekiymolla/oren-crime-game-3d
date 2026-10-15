import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../engine/game.dart';

/// Патроны "в магазине / в запасе" и полоска перезарядки. Опрашивает
/// [Game.weapon] своим Ticker'ом, как WantedStars.
class AmmoCounter extends StatefulWidget {
  const AmmoCounter({super.key, required this.game});

  final Game game;

  @override
  State<AmmoCounter> createState() => _AmmoCounterState();
}

class _AmmoCounterState extends State<AmmoCounter> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _magazine = -1;
  int _reserve = -1;
  double _reload = 0.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _check())..start();
  }

  void _check() {
    final weapon = widget.game.weapon;
    final reload = weapon.reloadProgress;
    if (weapon.ammoInMagazine != _magazine || weapon.reserveAmmo != _reserve || (reload - _reload).abs() > 0.02) {
      setState(() {
        _magazine = weapon.ammoInMagazine;
        _reserve = weapon.reserveAmmo;
        _reload = reload;
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(blurRadius: 3, color: Colors.black)];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '${widget.game.weapon.config.displayName}  $_magazine / $_reserve',
          style: TextStyle(
            color: _magazine == 0 ? Colors.redAccent : Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            shadows: shadow,
          ),
        ),
        if (_reload > 0.0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              width: 80,
              height: 4,
              child: LinearProgressIndicator(
                value: _reload,
                backgroundColor: Colors.white24,
                color: Colors.amber,
              ),
            ),
          ),
      ],
    );
  }
}

/// Прицел в центре экрана — только пока целимся (камера за плечом,
/// см. GameCameraController): луч прицела идёт ровно через центр.
class Crosshair extends StatefulWidget {
  const Crosshair({super.key, required this.game});

  final Game game;

  @override
  State<Crosshair> createState() => _CrosshairState();
}

class _CrosshairState extends State<Crosshair> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final visible = widget.game.isAiming;
      if (visible != _visible) setState(() => _visible = visible);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return const IgnorePointer(
      child: Center(child: CustomPaint(size: Size(28, 28), painter: _CrosshairPainter())),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outline = Paint()
      ..color = Colors.black54
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    final line = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    const gap = 4.0;
    const length = 8.0;
    for (final paint in [outline, line]) {
      canvas.drawLine(center + const Offset(gap, 0), center + const Offset(gap + length, 0), paint);
      canvas.drawLine(center - const Offset(gap, 0), center - const Offset(gap + length, 0), paint);
      canvas.drawLine(center + const Offset(0, gap), center + const Offset(0, gap + length), paint);
      canvas.drawLine(center - const Offset(0, gap), center - const Offset(0, gap + length), paint);
    }
    canvas.drawCircle(center, 1.4, line);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
