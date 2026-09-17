import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../police/arrest_state.dart';

/// Баннер "ЗАДЕРЖАН" на пару секунд после ареста (см. ArrestState) —
/// опрашивает состояние каждый кадр через свой Ticker, как WantedStars
/// (см. wanted_stars.dart), не перестраивая весь GameHud.
class ArrestBanner extends StatefulWidget {
  const ArrestBanner({super.key});

  @override
  State<ArrestBanner> createState() => _ArrestBannerState();
}

class _ArrestBannerState extends State<ArrestBanner> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _check())..start();
  }

  void _check() {
    final visible = arrestState.isRecent;
    if (visible != _visible) setState(() => _visible = visible);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'ЗАДЕРЖАН',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
            ),
          ),
        ),
      ),
    );
  }
}
