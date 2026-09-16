import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/input/input_state.dart';

/// Клавиатурный ввод для десктоп-тестирования (WASD/стрелки — движение,
/// Shift — бег, Space — прыжок, E — сесть/выйти из машины). Пишет в тот же
/// [InputState], что и тач-джойстик/кнопки — не отдельный путь ввода, а ещё
/// один источник для того же приёмника (см. InputState).
///
/// Удерживаемые клавиши (WASD/Shift) опрашиваются каждый кадр через
/// [HardwareKeyboard.instance.logicalKeysPressed], а не копятся по
/// down/up-событиям в onKeyEvent: на части платформ (в т.ч. проброс
/// клавиатуры хоста в Android-эмулятор) автоповтор зажатой клавиши приходит
/// как быстрые пары "отпустил-нажал", а не честное "держится" — из-за этого
/// накопленное по событиям состояние дёргается. Опрос текущего состояния
/// клавиатуры эту дёрготню убирает. Одноразовые действия (прыжок, посадка в
/// машину) по-прежнему берутся из onKeyEvent — они и должны срабатывать
/// один раз на нажатие, а не непрерывно, пока клавиша зажата.
class KeyboardControls extends StatefulWidget {
  const KeyboardControls({super.key, required this.onInteract, required this.child});

  /// Вызывается по 'E' — сесть/выйти из машины (Game.toggleVehicle).
  final VoidCallback onInteract;
  final Widget child;

  @override
  State<KeyboardControls> createState() => _KeyboardControlsState();
}

class _KeyboardControlsState extends State<KeyboardControls>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  // Клавиатура — не единственный источник ввода (есть ещё джойстик и
  // кнопки вождения на тач-экране, пишущие в тот же InputState). Если бы
  // мы безусловно писали (0,0)/false каждый кадр, когда клавиши не зажаты,
  // это забивало бы тач-ввод 60 раз в секунду сразу после его нажатия.
  // Поэтому пишем в InputState только пока клавиатура реально активна, плюс
  // один кадр на отпускание (чтобы честно остановить движение/бег, начатые
  // именно клавиатурой) — а дальше не трогаем InputState вообще.
  bool _wasMoving = false;
  bool _wasRunning = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _pollHeldKeys())..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _pollHeldKeys() {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final forward =
        pressed.contains(LogicalKeyboardKey.keyW) || pressed.contains(LogicalKeyboardKey.arrowUp);
    final back =
        pressed.contains(LogicalKeyboardKey.keyS) || pressed.contains(LogicalKeyboardKey.arrowDown);
    final left =
        pressed.contains(LogicalKeyboardKey.keyA) || pressed.contains(LogicalKeyboardKey.arrowLeft);
    final right =
        pressed.contains(LogicalKeyboardKey.keyD) || pressed.contains(LogicalKeyboardKey.arrowRight);
    final running = pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);

    var x = (right ? 1.0 : 0.0) - (left ? 1.0 : 0.0);
    var y = (forward ? 1.0 : 0.0) - (back ? 1.0 : 0.0);
    if (x != 0 && y != 0) {
      final len = math.sqrt(x * x + y * y);
      x /= len;
      y /= len;
    }

    final isMoving = x != 0 || y != 0;
    if (isMoving || _wasMoving) {
      inputState.setMove(x, y);
    }
    _wasMoving = isMoving;

    if (running || _wasRunning) {
      inputState.isRunning = running;
    }
    _wasRunning = running;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      inputState.requestJump();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyE) {
      widget.onInteract();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
