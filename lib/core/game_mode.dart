/// Кто сейчас управляется вводом игрока. Отдельный расшаренный стейт вместо
/// прямых ссылок между PlayerInputBridgeComponent и VehicleInputBridgeComponent
/// — оба просто проверяют текущий режим, не зная друг о друге.
enum ControlMode { onFoot, driving }

class GameModeState {
  ControlMode mode = ControlMode.onFoot;
}

final GameModeState gameModeState = GameModeState();
