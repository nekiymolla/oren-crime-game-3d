import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';

import 'game.dart';

/// Отрисовывает уже загруженную сцену. Владение [Game] (создание, load(),
/// отслеживание готовности) — на вызывающей стороне (см. GameHud), чтобы тот
/// же экземпляр Game был доступен для подключения CameraControls.
class GameView extends StatelessWidget {
  const GameView({super.key, required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    // camera: не передаём — используется активная камера сцены
    // (CameraComponent(activateOnMount: true) в Game.load).
    return SceneView(
      game.scene,
      onTick: (elapsed, dt) => game.tick(dt),
    );
  }
}
