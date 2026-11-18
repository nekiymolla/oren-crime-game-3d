import 'dart:convert';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import '../game.dart';
import 'frame_metrics.dart';

/// Opt-in, repeatable AOT benchmark. Excluded from ordinary play.
/// flutter run --profile -d macos --dart-define=PERF_BENCHMARK=true
class PerformanceProbe with WidgetsBindingObserver {
  PerformanceProbe(this.game) {
    SchedulerBinding.instance.addTimingsCallback(_frames);
    WidgetsBinding.instance.addObserver(this);
  }
  static const enabled = bool.fromEnvironment('PERF_BENCHMARK');
  final Game game;
  final _clock = Stopwatch()..start();
  final _timings = <FrameTiming>[];
  int _stage = -1;
  static bool completed = false;
  final _sceneTimes = <int>[];
  final _movingIntervals = <double>[];
  int? _lastMoving;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (completed) return;
    _clock
      ..stop()
      ..reset();
    _timings.clear();
    _sceneTimes.clear();
    _stage = -1;
    if (state == AppLifecycleState.resumed) _clock.start();
  }

  bool get nativeResolution =>
      _stage >= 0 &&
      _stage < variants.length &&
      variants[_stage] == 'native-resolution';
  static const requestedVariant = String.fromEnvironment('PERF_VARIANT');
  static const variants = requestedVariant == 'paired'
      ? ['drive', 'night-drive', 'drive-repeat', 'night-repeat']
      : [
          'drive',
          'night-drive',
          'drive-repeat',
          'night-repeat',
          'native-resolution',
          'legacy-drive',
        ];
  void _frames(List<FrameTiming> frames) {
    if (_stage >= 0 &&
        _stage < variants.length &&
        _clock.elapsedMilliseconds % 15000 > 3000) {
      _timings.addAll(frames);
    }
  }

  void tick() {
    final stage = _clock.elapsedMilliseconds ~/ 15000;
    if (stage != _stage) {
      if (_stage >= 0 && _stage < variants.length) _report();
      _stage = stage;
      if (stage >= variants.length) {
        SchedulerBinding.instance.removeTimingsCallback(_frames);
        WidgetsBinding.instance.removeObserver(this);
        completed = true;
        game.finishPerformanceScenario();
        return;
      }
      _timings.clear();
      _sceneTimes.clear();
      _movingIntervals.clear();
      _lastMoving = null;
      game.configurePerformanceScenario(variants[stage]);
    }
    if (stage >= 0 && stage < variants.length) {
      game.setPerformanceThrottle();
    }
  }

  void recordRenderedFrame(int now) {
    if (_stage < 0 ||
        _stage >= variants.length ||
        _clock.elapsedMilliseconds % 15000 <= 3000) {
      return;
    }
    if (_sceneTimes.isNotEmpty && _sceneTimes.last == now) return;
    _sceneTimes.add(now);
    if (game.vehicle.controller.speed > 2) {
      if (_lastMoving != null) {
        _movingIntervals.add((now - _lastMoving!) / 1000);
      }
      _lastMoving = now;
    } else {
      _lastMoving = null;
    }
  }

  void _report() {
    final frames = _timings;
    if (frames.length < 2) return;
    final metrics = measureFrames(
      _sceneTimes,
      frames.map((f) => f.totalSpan.inMicroseconds).toList(),
    );
    final gaps = <double>[
      for (var i = 1; i < _sceneTimes.length; i++)
        (_sceneTimes[i] - _sceneTimes[i - 1]) / 1000,
    ]..sort();
    _movingIntervals.sort();
    final movingFps = _movingIntervals.isEmpty
        ? null
        : 1000 *
              _movingIntervals.length /
              _movingIntervals.fold<double>(0, (a, b) => a + b);
    final movingP95 = _movingIntervals.isEmpty
        ? null
        : _movingIntervals[((_movingIntervals.length - 1) * .95).ceil()];
    // ignore: avoid_print
    print(
      'PERF ${jsonEncode({'scenario': variants[_stage], 'movingSamples': _movingIntervals.length, 'movingFps': movingFps, 'movingP95Ms': movingP95, 'sceneFrames': _sceneTimes.length, 'flutterFrames': frames.length, 'fps': metrics.fps, 'p95Ms': metrics.p95Ms, 'maxMs': gaps.isEmpty ? null : gaps.last, 'over25Ms': gaps.where((v) => v > 25.1).length, 'uiMs': frames.fold<int>(0, (n, f) => n + f.buildDuration.inMicroseconds) / frames.length / 1000, 'rasterMs': frames.fold<int>(0, (n, f) => n + f.rasterDuration.inMicroseconds) / frames.length / 1000, 'speed': game.vehicle.controller.speed, 'position': game.trackedNode.position.toString()})}',
    );
  }
}
