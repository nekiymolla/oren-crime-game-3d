import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';

import '../../engine/game.dart';
import '../../engine/game_view.dart';
import '../controls/vehicle_button.dart';
import '../controls/virtual_joystick.dart';

/// Высота нижней полосы с джойстиком/кнопками — под ней CameraControls не
/// перехватывает жесты, иначе drag по джойстику конкурировал бы за жест с
/// drag-поворотом камеры (два GestureDetector на одной точке экрана).
const double _controlsStripHeight = 190;

/// 3D-сцена плюс наложенные элементы управления. Раскладка контролов
/// подстраивается под ориентацию (уже, но выше в портрете; шире и ниже в
/// ландшафте — как в TES: Blades), а не фиксируется на одной ориентации.
class GameHud extends StatefulWidget {
  const GameHud({super.key});

  @override
  State<GameHud> createState() => _GameHudState();
}

class _GameHudState extends State<GameHud> {
  final Game game = Game();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    game.load().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const ColoredBox(
        color: Color(0xFF101418),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return OrientationBuilder(
      builder: (context, orientation) {
        final isPortrait = orientation == Orientation.portrait;
        final bottomInset = MediaQuery.of(context).padding.bottom;
        return Stack(
          fit: StackFit.expand,
          children: [
            GameView(game: game),
            // Drag в этой зоне (весь экран выше полосы управления) вращает
            // камеру вокруг игрока — как ПКМ/правый стик в GTA.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              bottom: _controlsStripHeight + bottomInset,
              // Listener — поверх CameraControls, не в конкуренции с ним за
              // жест (raw pointer, не гео-recognizer): просто отмечает, что
              // палец сейчас в зоне поворота, чтобы Game.tick не пытался
              // одновременно довернуть камеру за курсом машины (см.
              // userIsAdjustingCamera в Game).
              child: Listener(
                onPointerDown: (_) => game.userIsAdjustingCamera = true,
                onPointerUp: (_) => game.userIsAdjustingCamera = false,
                onPointerCancel: (_) => game.userIsAdjustingCamera = false,
                child: CameraControls(
                  controller: game.cameraController,
                  autofocus: false,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            Positioned(
              left: 24,
              bottom: bottomInset + (isPortrait ? 32 : 16),
              child: const VirtualJoystick(),
            ),
            Positioned(
              right: 24,
              bottom: bottomInset + (isPortrait ? 96 : 76),
              child: const JumpButton(),
            ),
            Positioned(
              right: 24,
              bottom: bottomInset + (isPortrait ? 24 : 16),
              child: const RunButton(),
            ),
            Positioned(
              left: 24,
              top: MediaQuery.of(context).padding.top + 16,
              child: VehicleButton(onPressed: game.toggleVehicle),
            ),
          ],
        );
      },
    );
  }
}
