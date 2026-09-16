import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/game_mode.dart';
import '../../engine/game.dart';

/// Показывает [VehicleButton], только когда есть смысл его нажимать: игрок
/// уже за рулём (тогда это "выйти"), либо в радиусе посадки от машины
/// (тогда "сесть"). Проверяет дистанцию каждый кадр через Ticker — не через
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
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _check())..start();
  }

  void _check() {
    final visible = gameModeState.mode == ControlMode.driving || _isPlayerNear();
    if (visible != _visible) setState(() => _visible = visible);
  }

  bool _isPlayerNear() {
    final playerPos = widget.game.playerNode.globalTransform.getTranslation();
    final vehiclePos = widget.game.vehicle.node.globalTransform.getTranslation();
    return (playerPos - vehiclePos).length <= Game.vehicleInteractRadius;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return VehicleButton(onPressed: widget.onToggle);
  }
}

/// Кнопка "сесть/выйти из машины". Сама ничего не решает — просто дёргает
/// переданный колбэк (Game.toggleVehicle). Видимость — забота
/// [VehicleInteractButton].
class VehicleButton extends StatelessWidget {
  const VehicleButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.12),
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: const Icon(Icons.directions_car, color: Colors.white70),
      ),
    );
  }
}
