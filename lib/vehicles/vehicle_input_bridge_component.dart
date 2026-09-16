import 'package:flutter_scene/scene.dart';

import '../core/game_mode.dart';
import '../core/input/input_state.dart';
import 'vehicle_controller_component.dart';

/// Передаёт джойстик в машину, только когда активен режим вождения (см.
/// [GameModeState]) — тот же джойстик, что и для ходьбы, но x = руль,
/// y = газ/тормоз. Отдельные педали/руль — будущее улучшение управления.
class VehicleInputBridgeComponent extends Component {
  VehicleInputBridgeComponent(this.controller);

  final VehicleControllerComponent controller;

  @override
  void update(double deltaSeconds) {
    if (gameModeState.mode != ControlMode.driving) {
      controller.setInput(throttle: 0, steer: 0);
      return;
    }
    controller.setInput(
      throttle: inputState.moveDirection.y,
      steer: inputState.moveDirection.x,
    );
  }
}
