import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';

import 'debug/fps_overlay.dart';
import 'game.dart';

/// Отрисовывает уже загруженную сцену. Владение [Game] (создание, load(),
/// отслеживание готовности) — на вызывающей стороне (см. GameHud), чтобы тот
/// же экземпляр Game был доступен для подключения CameraControls.
class GameView extends StatelessWidget {
  const GameView({super.key, required this.game, this.debugOverlay});

  final Game game;

  /// Опционален — если задан, каждый тик пишет туда координаты
  /// отслеживаемого узла (см. Game.trackedNode), чтобы можно было сообщить
  /// точное место просадки FPS, не гадая по скриншоту (см. PROGRESS.md).
  final DebugOverlayController? debugOverlay;

  @override
  Widget build(BuildContext context) {
    // camera: не передаём — используется активная камера сцены
    // (CameraComponent(activateOnMount: true) в Game.load).
    return SceneView(
      game.scene,
      onTick: (elapsed, dt) {
        game.tick(dt);
        final pos = game.trackedNode.globalTransform.getTranslation();
        debugOverlay?.setLine(
          'pos',
          'x=${pos.x.toStringAsFixed(1)} z=${pos.z.toStringAsFixed(1)}',
        );
      },
    );
  }
}
