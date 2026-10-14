import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../time/day_night.dart';
import '../../weather/weather.dart';

/// Игровые часы в HUD. Как и WantedStars, опрашивает [clock] своим Ticker
/// и перестраивается, только когда сменилась минута.
class ClockHud extends StatefulWidget {
  const ClockHud({super.key, required this.clock, required this.weather});

  final GameClock clock;
  final WeatherSystem weather;

  @override
  State<ClockHud> createState() => _ClockHudState();
}

class _ClockHudState extends State<ClockHud> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  String _label = '';

  @override
  void initState() {
    super.initState();
    _label = _text();
    _ticker = createTicker((_) {
      final label = _text();
      if (label != _label) setState(() => _label = label);
    })..start();
  }

  String _text() => '${widget.clock.label} · ${widget.weather.kind.label}';

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
          // Без Material-предка Flutter подчёркивает текст жёлтым.
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}
