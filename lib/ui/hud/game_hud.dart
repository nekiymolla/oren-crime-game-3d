import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';

import '../../core/game_mode.dart';
import '../../core/input/input_state.dart';
import '../../engine/debug/fps_overlay.dart';
import '../../engine/debug/quality_debug_panel.dart';
import '../../engine/game.dart';
import '../../engine/game_view.dart';
import '../controls/driving_controls.dart';
import '../controls/keyboard_controls.dart';
import '../controls/vehicle_button.dart';
import '../controls/virtual_joystick.dart';
import '../controls/weapon_controls.dart';
import 'arrest_banner.dart';
import 'clock_hud.dart';
import 'wanted_stars.dart';
import 'weapon_hud.dart';

/// Высота нижней полосы с джойстиком/кнопками — под ней CameraControls не
/// перехватывает жесты, иначе drag по джойстику конкурировал бы за жест с
/// drag-поворотом камеры (два GestureDetector на одной точке экрана).
const double _controlsStripHeight = 190;

/// 3D-сцена плюс наложенные элементы управления. Раскладка контролов
/// подстраивается под ориентацию (уже, но выше в портрете; шире и ниже в
/// ландшафте — как в TES: Blades), а не фиксируется на одной ориентации.
/// Набор кнопок разный пешком/за рулём (см. gameModeState).
class GameHud extends StatefulWidget {
  const GameHud({super.key, this.debugOverlay});

  final DebugOverlayController? debugOverlay;

  @override
  State<GameHud> createState() => _GameHudState();
}

class _GameHudState extends State<GameHud> {
  final Game game = Game(debugShowRoadGraph: kDebugMode);
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    game.load().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  /// Переключение машины меняет набор кнопок HUD (джойстик <-> газ/руль),
  /// поэтому в отличие от VehicleInteractButton (сам следит за дистанцией
  /// через Ticker) этот путь явно дёргает setState — смена режима дискретна
  /// и происходит только по нажатию, лишний Ticker здесь не нужен.
  void _toggleVehicle() {
    // Кнопка огня исчезает вместе с пешим набором кнопок — палец с неё
    // уже не "отпустится", и после высадки стрельба шла бы сама.
    inputState.fireHeld = false;
    setState(() => game.toggleVehicle());
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const ColoredBox(
        color: Color(0xFF101418),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final isDriving = gameModeState.mode == ControlMode.driving;

    return KeyboardControls(
      onInteract: _toggleVehicle,
      child: OrientationBuilder(
        builder: (context, orientation) {
          final isPortrait = orientation == Orientation.portrait;
          final bottomInset = MediaQuery.of(context).padding.bottom;
          final controlsBottom = bottomInset + (isPortrait ? 24 : 16);
          return Stack(
            fit: StackFit.expand,
            children: [
              GameView(game: game, debugOverlay: widget.debugOverlay),
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
              Positioned.fill(child: Crosshair(game: game)),
              if (isDriving)
                DrivingControls(bottomPadding: controlsBottom)
              else ...[
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
                  right: 104,
                  bottom: bottomInset + (isPortrait ? 44 : 30),
                  child: const FireButton(),
                ),
                Positioned(
                  right: 120,
                  bottom: bottomInset + (isPortrait ? 136 : 120),
                  child: const ReloadButton(),
                ),
                Positioned(
                  right: 24,
                  bottom: bottomInset + (isPortrait ? 170 : 150),
                  child: AmmoCounter(game: game),
                ),
              ],
              Positioned(
                left: 24,
                top: MediaQuery.of(context).padding.top + 16,
                child: VehicleInteractButton(game: game, onToggle: _toggleVehicle),
              ),
              Positioned(
                right: 24,
                top: MediaQuery.of(context).padding.top + 16,
                child: const WantedStars(),
              ),
              // Часы — по центру сверху, под "чёлкой"/Dynamic Island.
              Positioned(
                left: 0,
                right: 0,
                top: MediaQuery.of(context).padding.top + 8,
                child: Center(child: ClockHud(clock: game.clock, weather: game.weather)),
              ),
              // Не kDebugMode, а !kReleaseMode: мерить производительность
              // можно только в --profile (в debug числа не значат ничего —
              // ассерты, нет AOT), а там kDebugMode уже false. Из релиза
              // ручка всё равно исчезает.
              if (!kReleaseMode)
                Positioned(
                  right: 24,
                  top: MediaQuery.of(context).padding.top + 72,
                  child: QualityDebugPanel(game: game),
                ),
              const ArrestBanner(),
            ],
          );
        },
      ),
    );
  }
}
