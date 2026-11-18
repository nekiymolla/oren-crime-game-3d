import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_scene/scene.dart';
import 'debug/fps_overlay.dart';
import 'debug/performance_probe.dart';
import 'frame_pacer.dart';
import 'game.dart';
import 'render_resolution.dart';
import '../core/platform.dart';

/// Owns the game clock: one simulation/render request per 60 Hz vsync slot.
/// The repaint boundary prevents HUD animations from re-encoding the 3D scene.
class GameView extends StatefulWidget {
  const GameView({
    super.key,
    required this.game,
    this.debugOverlay,
    this.paused = false,
  });
  final Game game;
  final bool paused;
  final DebugOverlayController? debugOverlay;
  @override
  State<GameView> createState() => _GameViewState();
}

class _GameViewState extends State<GameView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  final _pacer = FramePacer();
  bool _active = true;
  bool _sceneUpdated = false;
  final _renderRevision = ValueNotifier<int>(0);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _pacer.reset();
  }

  @override
  void didUpdateWidget(GameView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paused != widget.paused) _pacer.reset();
  }

  void _tick(Duration elapsed) {
    if (!_active || widget.paused) return;
    final dt = _pacer.advance(elapsed.inMicroseconds);
    if (dt == null) return;
    final game = widget.game;
    if (PerformanceProbe.enabled) game.performanceProbe.tick();
    final step = dt.clamp(0.0, .05);
    game.tick(step);
    game.scene.update(step);
    _sceneUpdated = true;
    final pos = game.trackedNode.globalTransform.getTranslation();
    widget.debugOverlay?.setLine(
      'pos',
      'x=${pos.x.toStringAsFixed(1)} z=${pos.z.toStringAsFixed(1)}',
    );
    _renderRevision.value++;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _renderRevision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ValueListenableBuilder<int>(
      valueListenable: _renderRevision,
      builder: (context, revision, child) {
        final native = MediaQuery.devicePixelRatioOf(context);
        final useBudget =
            desktopControls &&
            !(PerformanceProbe.enabled &&
                widget.game.performanceProbe.nativeResolution);
        final ratio = useBudget
            ? scenePixelRatio(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                devicePixelRatio: native,
                renderScale: widget.game.scene.renderScale,
                pixelBudget:
                    2304000 -
                    504000 *
                        (widget.game.dayNight.lighting?.nightFactor ?? 0).clamp(
                          0.0,
                          1.0,
                        ),
              )
            : native;
        widget.debugOverlay?.setLine(
          'render',
          '3D DPR ${ratio.toStringAsFixed(2)} / native ${native.toStringAsFixed(2)}',
        );
        return RepaintBoundary(
          child: SceneView(
            widget.game.scene,
            autoTick: false,
            pixelRatio: ratio,
            cameraBuilder: (_) {
              // A HUD/asset repaint outside our clock must not trigger the
              // engine's implicit wall-clock simulation update (especially paused).
              if (!_sceneUpdated) widget.game.scene.update(0);
              _sceneUpdated = false;
              final stamp = SchedulerBinding
                  .instance
                  .currentFrameTimeStamp
                  .inMicroseconds;
              widget.debugOverlay?.recordSceneFrame(stamp);
              if (PerformanceProbe.enabled) {
                widget.game.performanceProbe.recordRenderedFrame(stamp);
              }
              return widget.game.scene.camera!;
            },
          ),
        );
      },
    ),
  );
}
