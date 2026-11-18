import '../../engine/debug/performance_probe.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart' hide Material;

import '../../core/game_mode.dart';
import '../../core/platform.dart';
import '../controls/desktop_pointer_controls.dart';
import '../../core/input/input_state.dart';
import '../../engine/debug/fps_overlay.dart';
import '../../engine/debug/quality_debug_panel.dart';
import '../../engine/game.dart';
import '../../engine/game_view.dart';
import '../controls/driving_controls.dart';
import '../controls/keyboard_controls.dart';
import '../controls/property_button.dart';
import '../controls/bench_button.dart';
import '../controls/vehicle_button.dart';
import '../controls/virtual_joystick.dart';
import '../controls/weapon_controls.dart';
import 'arrest_banner.dart';
import 'clock_hud.dart';
import 'health_hud.dart';
import 'compass_hud.dart';
import 'money_hud.dart';
import 'radar.dart';
import 'radar_math.dart';
import 'speed_hud.dart';
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
  final Game game = Game();
  bool _ready = false;
  bool _showDebug = false;
  bool _paused = false;

  /// Карта района для радара; null — не загрузилась (радар без подложки).
  Minimap? _minimap;

  @override
  void initState() {
    super.initState();
    Minimap.load().then((map) {
      if (mounted) setState(() => _minimap = map);
    }, onError: (Object _) {});
    game.load().then((_) {
      if (PerformanceProbe.enabled) {
        game.onPerformanceScenarioChanged = () {
          if (mounted) setState(() {});
        };
      }
      if (mounted) setState(() => _ready = true);
    });
  }

  /// Переключение машины меняет набор кнопок HUD (джойстик <-> газ/руль),
  /// поэтому в отличие от VehicleInteractButton (сам следит за дистанцией
  /// через Ticker) этот путь явно дёргает setState — смена режима дискретна
  /// и происходит только по нажатию, лишний Ticker здесь не нужен.
  void _toggleVehicle() {
    if (game.isDead) return;
    // Кнопка огня исчезает вместе с пешим набором кнопок — палец с неё
    // уже не "отпустится", и после высадки стрельба шла бы сама.
    inputState.fireHeld = false;
    setState(() => game.toggleVehicle());
  }

  void _setPaused(bool paused) {
    if (!desktopControls || !mounted || _paused == paused) return;
    inputState.reset();
    game.userIsAdjustingCamera = false;
    setState(() => _paused = paused);
  }

  void _useProperty() {
    final interaction = game.propertyInteraction;
    if (interaction == null) return;
    if (interaction.owned) {
      if (interaction.canSave) game.saveGame();
    } else {
      game.buyNearbyProperty();
    }
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
      enabled: !_paused,
      onPause: () => _setPaused(!_paused),
      onFocusLost: () {
        if (!PerformanceProbe.enabled) _setPaused(true);
      },
      onRest: game.restAtBench,
      onProperty: _useProperty,
      onSound: () => game.audio.muted = !game.audio.muted,
      child: OrientationBuilder(
        builder: (context, orientation) {
          final desktop = desktopControls;
          final isPortrait = !desktop && orientation == Orientation.portrait;
          final padding = MediaQuery.of(context).padding;
          final bottomInset = padding.bottom;
          final controlsBottom = bottomInset + (isPortrait ? 24 : 16);
          // Прозрачный Material — тексты HUD без него рисуются стилем
          // "нет Material-предка" (жёлтое двойное подчёркивание).
          return Material(
            type: MaterialType.transparency,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GameView(
                  game: game,
                  debugOverlay: widget.debugOverlay,
                  paused: _paused,
                ),
                if (desktop)
                  Positioned.fill(
                    child: DesktopPointerControls(
                      enabled: !_paused,
                      onFocus: () => KeyboardControls.requestFocus(context),
                      onLooking: (value) => game.userIsAdjustingCamera = value,
                      onLook: game.cameraController.handleDragUpdate,
                      onViewport: (size) =>
                          game.cameraController.viewportSize = size,
                    ),
                  ),
                // Drag в этой зоне (весь экран выше полосы управления) вращает
                // камеру вокруг игрока — как ПКМ/правый стик в GTA.
                if (!desktop)
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
                      onPointerCancel: (_) =>
                          game.userIsAdjustingCamera = false,
                      child: CameraControls(
                        controller: game.cameraController,
                        autofocus: false,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                Positioned.fill(child: Crosshair(game: game)),
                if (!desktop && isDriving)
                  DrivingControls(bottomPadding: controlsBottom)
                else if (!desktop) ...[
                  Positioned(
                    left: padding.left + 24,
                    bottom: bottomInset + (isPortrait ? 32 : 16),
                    child: const VirtualJoystick(),
                  ),
                  Positioned(
                    right: padding.right + 24,
                    bottom: bottomInset + (isPortrait ? 96 : 76),
                    child: const JumpButton(),
                  ),
                  Positioned(
                    right: padding.right + 24,
                    bottom: bottomInset + (isPortrait ? 24 : 16),
                    child: const RunButton(),
                  ),
                  Positioned(
                    right: padding.right + 104,
                    bottom: bottomInset + (isPortrait ? 44 : 30),
                    child: const FireButton(),
                  ),
                  Positioned(
                    right: padding.right + 120,
                    bottom: bottomInset + (isPortrait ? 136 : 120),
                    child: const ReloadButton(),
                  ),
                  Positioned(
                    right: padding.right + 24,
                    bottom: bottomInset + (isPortrait ? 170 : 150),
                    child: AmmoCounter(game: game),
                  ),
                ],
                if (desktop && !isDriving)
                  Positioned(
                    right: 24,
                    bottom: 30,
                    child: AmmoCounter(game: game),
                  ),
                // Навигация и состояние (в духе GTA IV): в горизонтальном
                // режиме — круглый радар слева сверху (обод: слева
                // бронежилет, справа здоровье), в вертикальном — плоский
                // компас во всю ширину с теми же полосами по краям.
                if (isPortrait)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: padding.top + 6,
                    child: CompassHud(game: game),
                  )
                else
                  Positioned(
                    left: padding.left + 12,
                    top: padding.top + 10,
                    child: RadarHud(game: game, minimap: _minimap),
                  ),
                Positioned(
                  left: isPortrait ? 24 : padding.left + 12 + 150 + 12,
                  top: padding.top + (isPortrait ? 52 : 14),
                  child: VehicleInteractButton(
                    game: game,
                    onToggle: _toggleVehicle,
                  ),
                ),
                Positioned(
                  right: padding.right + 24,
                  top: padding.top + (isPortrait ? 52 : 14),
                  child: const WantedStars(),
                ),
                Positioned(
                  right: padding.right + 24,
                  top: padding.top + (isPortrait ? 80 : 42),
                  child: MoneyHud(wallet: game.wallet),
                ),
                // Часы — по центру: в портрете под компасом, в ландшафте
                // сверху.
                Positioned(
                  left: 0,
                  right: 0,
                  top: padding.top + (isPortrait ? 50 : 8),
                  child: Center(
                    child: ClockHud(clock: game.clock, weather: game.weather),
                  ),
                ),
                // Не kDebugMode, а !kReleaseMode: мерить производительность
                // можно только в --profile (в debug числа не значат ничего —
                // ассерты, нет AOT), а там kDebugMode уже false. Из релиза
                // ручка всё равно исчезает.
                if (!kReleaseMode)
                  Positioned(
                    left: padding.left + 12,
                    top: padding.top + (isPortrait ? 124 : 174),
                    child: IconButton.filledTonal(
                      tooltip: _showDebug
                          ? 'Скрыть диагностику'
                          : 'Диагностика',
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() {
                        _showDebug = !_showDebug;
                        widget.debugOverlay?.visible = _showDebug;
                      }),
                      icon: Icon(_showDebug ? Icons.close : Icons.tune),
                    ),
                  ),
                if (!kReleaseMode && _showDebug)
                  Positioned(
                    right: 24,
                    top: padding.top + (isPortrait ? 130 : 92),
                    child: QualityDebugPanel(game: game),
                  ),
                Positioned.fill(child: HealthHud(game: game)),
                if (isDriving)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: controlsBottom + 12,
                    child: Center(child: SpeedHud(game: game)),
                  ),
                // Кнопка дома — по центру над полосой управления, у маркера.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: desktop
                      ? 96
                      : _controlsStripHeight +
                            MediaQuery.of(context).padding.bottom +
                            12,
                  child: Center(child: PropertyButton(game: game)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: desktop ? 52 : controlsBottom + 14,
                  child: Center(child: BenchButton(game: game)),
                ),
                Positioned(
                  left: padding.left + 10,
                  bottom: 2,
                  child: GestureDetector(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Картографические данные'),
                        content: const SelectableText(
                          '© OpenStreetMap contributors\nЛицензия ODbL 1.0\nhttps://www.openstreetmap.org/copyright\n\nДорожки и площадки — по карте. Фонари, лавочки, посадки деревьев, ограды и оборудование размещены приблизительно.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Закрыть'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text(
                      '© OpenStreetMap contributors · ODbL',
                      style: TextStyle(color: Colors.white54, fontSize: 9),
                    ),
                  ),
                ),
                if (desktop)
                  Positioned(
                    left: 12,
                    bottom: 22,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isDriving
                              ? 'WASD / стрелки · вождение   Space · ручник   E · выйти   Esc · пауза'
                              : 'WASD · ходьба   Shift · бег   Space · прыжок   E · машина\nЛКМ · огонь   Мышь / тачпад · камера   ПКМ · прицел   R · перезарядка   B · отдых',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (desktop)
                  Positioned(
                    right: 16,
                    top: 80,
                    child: IconButton.filledTonal(
                      tooltip: 'Пауза · Esc',
                      onPressed: () => _setPaused(true),
                      icon: const Icon(Icons.pause),
                    ),
                  ),
                if (_paused)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: .65),
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Пауза',
                                  style: TextStyle(fontSize: 28),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'WASD / стрелки — движение\nShift — бег\nSpace — прыжок / ручник\nE — сесть в машину / выйти\nКлик по сцене — захват курсора\nМышь / тачпад — камера, ПКМ — прицел\nЛКМ или F — огонь\nR — перезарядка\nB — передохнуть у лавочки\nH — купить дом / сохранить игру\nM — включить / выключить звук',
                                ),
                                const SizedBox(height: 20),
                                FilledButton(
                                  onPressed: () {
                                    _setPaused(false);
                                    KeyboardControls.requestFocus(context);
                                  },
                                  child: const Text('Продолжить · Esc'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                const ArrestBanner(),
                const DeathBanner(),
              ],
            ),
          );
        },
      ),
    );
  }
}
