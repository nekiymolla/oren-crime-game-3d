import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';

import '../core/input/input_state.dart';

/// Передаёт команды из [InputState] (не знает о движке) в готовые
/// [ThirdPersonControllerComponent] и [FollowCameraController] flutter_scene
/// (не знают об InputState). Развязка нужна, чтобы позже игрока можно было
/// водить сетевым вводом или AI-повтором без изменений в этом мосте.
///
/// Движение camera-relative: "вперёд" на джойстике — это "от камеры", а не
/// "куда сейчас смотрит персонаж" (см. cameraHeadingYaw в setMoveInput) —
/// иначе после разворота камеры вокруг игрока джойстик вёл бы в неожиданную
/// сторону.
class PlayerInputBridgeComponent extends Component {
  PlayerInputBridgeComponent(this.movement, this.camera);

  final ThirdPersonControllerComponent movement;
  final FollowCameraController camera;

  @override
  void update(double deltaSeconds) {
    movement.setMoveInput(
      inputState.moveDirection,
      isRunning: inputState.isRunning,
      cameraHeadingYaw: camera.yaw,
    );
    if (inputState.consumeJump()) {
      movement.jump();
    }
  }
}
