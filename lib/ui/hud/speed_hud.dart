import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../engine/game.dart';

/// Only repaints when the displayed speed changes, independently of the HUD.
class SpeedHud extends StatefulWidget {
  const SpeedHud({super.key, required this.game});

  final Game game;

  @override
  State<SpeedHud> createState() => _SpeedHudState();
}

class _SpeedHudState extends State<SpeedHud>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _speed = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final speed = (widget.game.vehicle.controller.speed * 3.6).round();
      if (speed != _speed) setState(() => _speed = speed);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$_speed', style: const TextStyle(fontSize: 30)),
            const TextSpan(
              text: '  км/ч',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ),
  );
}
