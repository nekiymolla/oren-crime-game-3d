import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../core/game_mode.dart';
import '../core/input/input_state.dart';
import 'character_controller_component.dart';

/// Передаёт команды из [InputState] (не знает о движке) в наш
/// [CharacterControllerComponent] и готовый [FollowCameraController]
/// flutter_scene (не знают об InputState). Развязка нужна, чтобы позже игрока
/// можно было водить сетевым вводом или AI-повтором без изменений в этом
/// мосте.
///
/// Движение camera-relative: "вперёд" на джойстике — это "от камеры", а не
/// "куда сейчас смотрит персонаж" (см. cameraHeadingYaw в setMoveInput) —
/// иначе после разворота камеры вокруг игрока джойстик вёл бы в неожиданную
/// сторону.
class PlayerInputBridgeComponent extends Component {
  PlayerInputBridgeComponent(this.movement, this.camera);

  final CharacterControllerComponent movement;
  final FollowCameraController camera;

  @override
  void update(double deltaSeconds) {
    // За рулём контроллер персонажа вообще не тикает: раньше он продолжал
    // считать гравитацию и лучи невидимому игроку, а ввод в него не писался
    // (мост выходил раньше), так что персонаж ещё и уезжал с последним
    // ненулевым вводом. enabled — штатное поле Component.
    if (gameModeState.mode != ControlMode.onFoot) {
      if (movement.enabled) {
        movement.setMoveInput(vm.Vector2.zero());
        movement.enabled = false;
      }
      return;
    }
    if (!movement.enabled) movement.enabled = true;
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
