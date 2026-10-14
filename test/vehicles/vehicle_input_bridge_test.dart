import 'package:crime_oren/core/game_mode.dart';
import 'package:crime_oren/core/input/input_state.dart';
import 'package:crime_oren/vehicles/vehicle_controller_component.dart';
import 'package:crime_oren/vehicles/vehicle_input_bridge_component.dart';
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('джойстик рулит только активной машиной, брошенная стоит', () {
    (VehicleControllerComponent, VehicleInputBridgeComponent) car() {
      final controller = VehicleControllerComponent(maxSpeed: 40, acceleration: 10, braking: 20);
      final bridge = VehicleInputBridgeComponent(controller);
      Node()
        ..addComponent(controller)
        ..addComponent(bridge);
      return (controller, bridge);
    }

    final (stolen, stolenBridge) = car();
    final (abandoned, abandonedBridge) = car();
    gameModeState
      ..mode = ControlMode.driving
      ..activeVehicle = stolen;
    inputState.moveDirection = vm.Vector2(0, 1);

    for (var i = 0; i < 60; i++) {
      for (final (controller, bridge) in [(stolen, stolenBridge), (abandoned, abandonedBridge)]) {
        bridge.update(1 / 60);
        controller.fixedUpdate(1 / 60);
      }
    }
    expect(stolen.speed, greaterThan(1.0));
    expect(abandoned.speed, 0.0);

    gameModeState
      ..mode = ControlMode.onFoot
      ..activeVehicle = null;
    inputState.moveDirection = vm.Vector2.zero();
  });
}
