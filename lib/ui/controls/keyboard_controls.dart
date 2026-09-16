import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/input/input_state.dart';

/// Клавиатурный ввод для десктоп-тестирования (WASD/стрелки — движение,
/// Shift — бег, Space — прыжок, E — сесть/выйти из машины). Пишет в тот же
/// [InputState], что и тач-джойстик/кнопки — не отдельный путь ввода, а ещё
/// один источник для того же приёмника (см. InputState).
///
/// Один и тот же WASD работает и пешком, и за рулём — режим определяет, кто
/// сейчас читает InputState (см. GameModeState), сама клавиатура об этом не
/// знает.
class KeyboardControls extends StatefulWidget {
  const KeyboardControls({super.key, required this.onInteract, required this.child});

  /// Вызывается по 'E' — сесть/выйти из машины (Game.toggleVehicle).
  final VoidCallback onInteract;
  final Widget child;

  @override
  State<KeyboardControls> createState() => _KeyboardControlsState();
}

class _KeyboardControlsState extends State<KeyboardControls> {
  bool _forward = false;
  bool _back = false;
  bool _left = false;
  bool _right = false;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;

    if (key == LogicalKeyboardKey.keyW || key == LogicalKeyboardKey.arrowUp) {
      _forward = isDown;
    } else if (key == LogicalKeyboardKey.keyS || key == LogicalKeyboardKey.arrowDown) {
      _back = isDown;
    } else if (key == LogicalKeyboardKey.keyA || key == LogicalKeyboardKey.arrowLeft) {
      _left = isDown;
    } else if (key == LogicalKeyboardKey.keyD || key == LogicalKeyboardKey.arrowRight) {
      _right = isDown;
    } else if (key == LogicalKeyboardKey.shiftLeft || key == LogicalKeyboardKey.shiftRight) {
      inputState.isRunning = isDown;
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.space) {
      if (isDown) inputState.requestJump();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.keyE) {
      if (isDown) widget.onInteract();
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }

    _recomputeMove();
    return KeyEventResult.handled;
  }

  void _recomputeMove() {
    var x = (_right ? 1.0 : 0.0) - (_left ? 1.0 : 0.0);
    var y = (_forward ? 1.0 : 0.0) - (_back ? 1.0 : 0.0);
    if (x != 0 && y != 0) {
      final len = math.sqrt(x * x + y * y);
      x /= len;
      y /= len;
    }
    inputState.setMove(x, y);
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }
}
