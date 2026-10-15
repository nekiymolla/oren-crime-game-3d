import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../engine/game.dart';
import '../../player/death_state.dart';
import '../../player/player_health.dart';

/// Красная вспышка по краям экрана при попадании. Сами полосы здоровья
/// и бронежилета — в радаре/компасе (radar.dart, compass_hud.dart).
/// Опрашивает [Game.playerHealth] своим Ticker'ом, как WantedStars.
class HealthHud extends StatefulWidget {
  const HealthHud({super.key, required this.game});

  final Game game;

  @override
  State<HealthHud> createState() => _HealthHudState();
}

class _HealthHudState extends State<HealthHud> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _health = PlayerHealth.maxHealth;
  double _flash = 0.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final health = widget.game.playerHealth.health;
      final flash = widget.game.playerHealth.damageFlash;
      if ((health - _health).abs() > 0.5 || (flash - _flash).abs() > 0.02) {
        setState(() {
          _health = health;
          _flash = flash;
        });
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_flash > 0.0)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.95,
                  colors: [Colors.transparent, Colors.red.withValues(alpha: 0.55 * _flash)],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Баннер после смерти игрока (см. DeathState), как "ЗАДЕРЖАН".
class DeathBanner extends StatefulWidget {
  const DeathBanner({super.key});

  @override
  State<DeathBanner> createState() => _DeathBannerState();
}

class _DeathBannerState extends State<DeathBanner> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final visible = deathState.isRecent;
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
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.35),
        child: const Center(
          child: Text(
            'ПОТРАЧЕНО',
            style: TextStyle(
              color: Color(0xFFE53935),
              fontSize: 40,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
              shadows: [Shadow(blurRadius: 8, color: Colors.black)],
            ),
          ),
        ),
      ),
    );
  }
}
