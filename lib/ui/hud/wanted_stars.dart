import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../police/wanted_state.dart';

/// Звёзды розыска в углу HUD. Опрашивает [wantedState] каждый кадр через
/// свой Ticker, как VehicleInteractButton (см. vehicle_button.dart) — не
/// перестраивает весь GameHud ради одного индикатора.
class WantedStars extends StatefulWidget {
  const WantedStars({super.key});

  @override
  State<WantedStars> createState() => _WantedStarsState();
}

class _WantedStarsState extends State<WantedStars> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _stars = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _check())..start();
  }

  void _check() {
    final stars = wantedState.stars;
    if (stars != _stars) setState(() => _stars = stars);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_stars == 0) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _stars; i++)
          const Padding(
            padding: EdgeInsets.only(left: 2),
            child: Icon(Icons.star, color: Colors.amber, size: 22),
          ),
      ],
    );
  }
}
