import 'package:flutter/material.dart';

import '../../core/input/input_state.dart';

/// Кнопки вождения — газ/тормоз справа, руль-влево/руль-вправо слева.
/// Отдельная раскладка от пешего джойстика: за рулём удобнее дискретные
/// "держать кнопку", чем целиться в маленький аналоговый стик.
///
/// Пишет в тот же [InputState.moveDirection], что и джойстик/клавиатура —
/// [VehicleInputBridgeComponent] не знает и не должен знать, откуда пришёл
/// ввод.
class DrivingControls extends StatefulWidget {
  const DrivingControls({super.key, required this.bottomPadding});

  final double bottomPadding;

  @override
  State<DrivingControls> createState() => _DrivingControlsState();
}

class _DrivingControlsState extends State<DrivingControls> {
  bool _accelerating = false;
  bool _braking = false;
  bool _steeringLeft = false;
  bool _steeringRight = false;

  void _recompute() {
    final throttle = (_accelerating ? 1.0 : 0.0) - (_braking ? 1.0 : 0.0);
    final steer = (_steeringRight ? 1.0 : 0.0) - (_steeringLeft ? 1.0 : 0.0);
    inputState.setMove(steer, throttle);
  }

  Widget _button({
    required IconData icon,
    required void Function(bool held) setHeld,
  }) {
    return Listener(
      onPointerDown: (_) => setState(() {
        setHeld(true);
        _recompute();
      }),
      onPointerUp: (_) => setState(() {
        setHeld(false);
        _recompute();
      }),
      onPointerCancel: (_) => setState(() {
        setHeld(false);
        _recompute();
      }),
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.14),
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: Icon(icon, color: Colors.white70, size: 32),
      ),
    );
  }

  @override
  void dispose() {
    // На случай выхода из машины с зажатой кнопкой — не оставляем висящий ввод.
    inputState.setMove(0, 0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Руль — левый нижний угол, пара кнопок влево/вправо.
        Positioned(
          left: 24,
          bottom: widget.bottomPadding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _button(icon: Icons.arrow_left, setHeld: (v) => _steeringLeft = v),
              const SizedBox(width: 12),
              _button(icon: Icons.arrow_right, setHeld: (v) => _steeringRight = v),
            ],
          ),
        ),
        // Газ/тормоз — правый нижний угол, друг над другом.
        Positioned(
          right: 24,
          bottom: widget.bottomPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _button(icon: Icons.arrow_upward, setHeld: (v) => _accelerating = v),
              const SizedBox(height: 12),
              _button(icon: Icons.arrow_downward, setHeld: (v) => _braking = v),
            ],
          ),
        ),
      ],
    );
  }
}
