import 'package:flutter/material.dart';

import '../../core/input/input_state.dart';

/// Джойстик движения для тача. Пишет напрямую в [inputState] — здесь нет
/// прямой ссылки на игрока или контроллер движения (см. InputState).
class VirtualJoystick extends StatefulWidget {
  const VirtualJoystick({super.key, this.size = 120});

  final double size;

  @override
  State<VirtualJoystick> createState() => _VirtualJoystickState();
}

class _VirtualJoystickState extends State<VirtualJoystick> {
  Offset _knobOffset = Offset.zero;

  void _updateFromLocalPosition(Offset localPosition) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final raw = localPosition - center;
    final maxRadius = widget.size / 2;
    final clamped = raw.distance > maxRadius
        ? raw / raw.distance * maxRadius
        : raw;
    setState(() => _knobOffset = clamped);

    final normalized = clamped / maxRadius;
    // Экранный low — положительный dy вниз; для геймплея "вперёд" — это
    // отрицательный dy, поэтому знак инвертируется здесь же, на входе.
    inputState.setMove(normalized.dx, -normalized.dy);
  }

  void _reset() {
    setState(() => _knobOffset = Offset.zero);
    inputState.setMove(0, 0);
  }

  @override
  Widget build(BuildContext context) {
    final knobSize = widget.size * 0.45;
    return GestureDetector(
      onPanStart: (details) => _updateFromLocalPosition(details.localPosition),
      onPanUpdate: (details) => _updateFromLocalPosition(details.localPosition),
      onPanEnd: (_) => _reset(),
      onPanCancel: _reset,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(color: Colors.white24, width: 2),
              ),
            ),
            Transform.translate(
              offset: _knobOffset,
              child: Container(
                width: knobSize,
                height: knobSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кнопка прыжка/бега — отдельный маленький виджет, тоже пишущий в
/// [inputState] напрямую, без ссылки на игровые объекты.
class RunButton extends StatelessWidget {
  const RunButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => inputState.isRunning = true,
      onPointerUp: (_) => inputState.isRunning = false,
      onPointerCancel: (_) => inputState.isRunning = false,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.12),
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: const Icon(Icons.directions_run, color: Colors.white70),
      ),
    );
  }
}

class JumpButton extends StatelessWidget {
  const JumpButton({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => inputState.requestJump(),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.12),
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: const Icon(Icons.arrow_upward, color: Colors.white70),
      ),
    );
  }
}
