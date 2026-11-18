import 'package:flutter/widgets.dart';
import 'package:flutter_scene/scene.dart';

import 'debug/fps_overlay.dart';
import 'game.dart';

/// Отрисовывает уже загруженную сцену. Владение [Game] (создание, load(),
/// отслеживание готовности) — на вызывающей стороне (см. GameHud), чтобы тот
/// же экземпляр Game был доступен для подключения CameraControls.
class GameView extends StatelessWidget {
  const GameView({
    super.key,
    required this.game,
    this.debugOverlay,
    this.paused = false,
  });

  final Game game;
  final bool paused;

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
        final step = paused ? 0.0 : dt.clamp(0.0, 0.05);
        if (!paused) game.tick(step);
        // Explicit time step prevents wall-clock catch-up after a paused or
        // backgrounded window. Render skips its own implicit component tick.
        game.scene.update(step);
        final pos = game.trackedNode.globalTransform.getTranslation();
        debugOverlay?.setLine(
          'pos',
          'x=${pos.x.toStringAsFixed(1)} z=${pos.z.toStringAsFixed(1)}',
        );
      },
    );
  }
}
