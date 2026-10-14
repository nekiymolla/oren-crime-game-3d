import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../engine/game.dart';

/// Показывает [VehicleButton], только когда есть смысл его нажимать: игрок
/// уже за рулём (тогда это "выйти"), либо в радиусе посадки от своей машины
/// ("сесть") или от медленной машины потока ("угнать" — кнопка красная).
/// Что именно — решает [Game.vehicleInteraction]. Проверяет дистанцию каждый кадр через Ticker — не через
/// перестройку всего GameHud, чтобы не дёргать весь Stack ради одной кнопки.
class VehicleInteractButton extends StatefulWidget {
  const VehicleInteractButton({super.key, required this.game, required this.onToggle});

  final Game game;

  /// Вызывается вместо game.toggleVehicle() напрямую — вызывающая сторона
  /// (GameHud) заодно пересобирает набор кнопок (джойстик <-> газ/руль).
  final VoidCallback onToggle;

  @override
  State<VehicleInteractButton> createState() => _VehicleInteractButtonState();
}

class _VehicleInteractButtonState extends State<VehicleInteractButton>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  VehicleInteraction? _interaction;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _check())..start();
  }

  void _check() {
    final interaction = widget.game.vehicleInteraction;
    if (interaction != _interaction) setState(() => _interaction = interaction);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final interaction = _interaction;
    if (interaction == null) return const SizedBox.shrink();
    return VehicleButton(onPressed: widget.onToggle, isCarjack: interaction == VehicleInteraction.carjack);
  }
}

/// Кнопка "сесть/выйти из машины". Сама ничего не решает — просто дёргает
/// переданный колбэк (Game.toggleVehicle). Видимость — забота
/// [VehicleInteractButton].
class VehicleButton extends StatelessWidget {
  const VehicleButton({super.key, required this.onPressed, this.isCarjack = false});

  final VoidCallback onPressed;

  /// Угон, а не посадка в свою — красная, чтобы было видно, что это
  /// преступление (розыск).
  final bool isCarjack;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isCarjack ? Colors.red.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.12),
          border: Border.all(color: isCarjack ? Colors.redAccent : Colors.white24, width: 2),
        ),
        child: Icon(isCarjack ? Icons.car_crash : Icons.directions_car, color: Colors.white70),
      ),
    );
  }
}
