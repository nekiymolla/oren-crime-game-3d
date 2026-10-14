/// Кто сейчас управляется вводом игрока. Отдельный расшаренный стейт вместо
/// прямых ссылок между PlayerInputBridgeComponent и VehicleInputBridgeComponent
/// — оба просто проверяют текущий режим, не зная друг о друге.
enum ControlMode { onFoot, driving }

class GameModeState {
  ControlMode mode = ControlMode.onFoot;

  /// Контроллер машины, за рулём которой игрок (VehicleControllerComponent;
  /// тип не указан, чтобы core не зависел от vehicles). Машин игрока в мире
  /// может быть несколько — своя и угнанные, — и джойстик должен рулить
  /// только этой, см. VehicleInputBridgeComponent.
  Object? activeVehicle;
}

final GameModeState gameModeState = GameModeState();
