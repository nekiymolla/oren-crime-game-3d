import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/input/input_state.dart';
import '../../core/game_mode.dart';

/// Клавиатурный ввод для десктоп-тестирования (WASD/стрелки — движение,
/// Shift — бег, Space — прыжок, E — сесть/выйти из машины, F — огонь
/// (удержание), R — перезарядка). Пишет в тот же
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
  const KeyboardControls({
    super.key,
    required this.onInteract,
    required this.child,
    this.enabled = true,
    this.onPause,
    this.onFocusLost,
    this.onRest,
    this.onProperty,
    this.onSound,
  });

  static void requestFocus(BuildContext context) {
    context
        .findAncestorStateOfType<_KeyboardControlsState>()
        ?._focus
        .requestFocus();
  }

  /// Вызывается по 'E' — сесть/выйти из машины (Game.toggleVehicle).
  final VoidCallback onInteract;
  final Widget child;
  final bool enabled;
  final VoidCallback? onPause, onFocusLost, onRest, onProperty, onSound;

  @override
  State<KeyboardControls> createState() => _KeyboardControlsState();
}

class _KeyboardControlsState extends State<KeyboardControls>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _focus = FocusNode(debugLabel: 'game keyboard');
  bool _active = true;
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
  bool _wasFiring = false;
  bool _wasHandbraking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker((_) => _pollHeldKeys())..start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _release();
    _focus.dispose();
    _ticker.dispose();
    super.dispose();
  }

  void _release() {
    inputState.reset();
    _wasMoving = _wasRunning = _wasFiring = _wasHandbraking = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      _release();
      widget.onFocusLost?.call();
    }
  }

  @override
  void didUpdateWidget(KeyboardControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _release();
  }

  void _pollHeldKeys() {
    if (!widget.enabled || !_active || !_focus.hasFocus) return;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final physical = HardwareKeyboard.instance.physicalKeysPressed;
    final forward =
        (physical.contains(PhysicalKeyboardKey.keyW) ||
            pressed.contains(LogicalKeyboardKey.keyW)) ||
        pressed.contains(LogicalKeyboardKey.arrowUp);
    final back =
        (physical.contains(PhysicalKeyboardKey.keyS) ||
            pressed.contains(LogicalKeyboardKey.keyS)) ||
        pressed.contains(LogicalKeyboardKey.arrowDown);
    final left =
        (physical.contains(PhysicalKeyboardKey.keyA) ||
            pressed.contains(LogicalKeyboardKey.keyA)) ||
        pressed.contains(LogicalKeyboardKey.arrowLeft);
    final right =
        (physical.contains(PhysicalKeyboardKey.keyD) ||
            pressed.contains(LogicalKeyboardKey.keyD)) ||
        pressed.contains(LogicalKeyboardKey.arrowRight);
    final running =
        pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);

    var x = (right ? 1.0 : 0.0) - (left ? 1.0 : 0.0);
    var y = (forward ? 1.0 : 0.0) - (back ? 1.0 : 0.0);
    if (gameModeState.mode == ControlMode.onFoot && x != 0 && y != 0) {
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

    final handbrake =
        gameModeState.mode == ControlMode.driving &&
        pressed.contains(LogicalKeyboardKey.space);
    if (handbrake || _wasHandbraking) inputState.handbrakeHeld = handbrake;
    _wasHandbraking = handbrake;

    final firing =
        (physical.contains(PhysicalKeyboardKey.keyF) ||
        pressed.contains(LogicalKeyboardKey.keyF));
    if (firing || _wasFiring) {
      inputState.keyboardFireHeld = firing;
    }
    _wasFiring = firing;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _release();
      widget.onPause?.call();
      return KeyEventResult.handled;
    }
    if (!widget.enabled) return KeyEventResult.ignored;
    if ((event.physicalKey == PhysicalKeyboardKey.keyB ||
        event.logicalKey == LogicalKeyboardKey.keyB)) {
      widget.onRest?.call();
      return KeyEventResult.handled;
    }
    if ((event.physicalKey == PhysicalKeyboardKey.keyH ||
        event.logicalKey == LogicalKeyboardKey.keyH)) {
      widget.onProperty?.call();
      return KeyEventResult.handled;
    }
    if ((event.physicalKey == PhysicalKeyboardKey.keyM ||
        event.logicalKey == LogicalKeyboardKey.keyM)) {
      widget.onSound?.call();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.space) {
      if (gameModeState.mode == ControlMode.onFoot) inputState.requestJump();
      return KeyEventResult.handled;
    }
    if ((event.physicalKey == PhysicalKeyboardKey.keyR ||
        event.logicalKey == LogicalKeyboardKey.keyR)) {
      inputState.requestReload();
      return KeyEventResult.handled;
    }
    if ((event.physicalKey == PhysicalKeyboardKey.keyE ||
        event.logicalKey == LogicalKeyboardKey.keyE)) {
      widget.onInteract();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      onFocusChange: (focused) {
        if (!focused) {
          _release();
          widget.onFocusLost?.call();
        }
      },
      child: widget.child,
    );
  }
}
