import 'package:vector_math/vector_math.dart' as vm;

/// Развязывает источник ввода (клавиатура, виртуальный джойстик) от того,
/// кто его использует (PlayerControllerComponent). Виджеты ввода пишут сюда,
/// компоненты игрока читают — прямых ссылок друг на друга у них нет.
class InputState {
  /// Направление движения в плоскости XZ: x — вправо, y — вперёд. Длина 0..1.
  vm.Vector2 moveDirection = vm.Vector2.zero();

  bool isRunning = false;

  /// Взводится нажатием прыжка, считывается и сбрасывается контроллером
  /// игрока за один кадр (edge-triggered, а не удержание).
  bool jumpRequested = false;

  void setMove(double x, double y) {
    moveDirection = vm.Vector2(x, y);
  }

  void requestJump() => jumpRequested = true;

  bool consumeJump() {
    final requested = jumpRequested;
    jumpRequested = false;
    return requested;
  }
}

/// Общий на игровую сессию экземпляр — как и [eventBus], доступ к нему через
/// composition root при старте приложения.
final InputState inputState = InputState();
