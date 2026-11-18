import 'dart:async';
import 'dart:collection';
import 'dart:ui' show FramePhase;

import 'frame_metrics.dart';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Оверлей только для разработки: FPS, время кадра и произвольные
/// debug-строки (координаты игрока, уровень розыска, загруженные чанки
/// и т.д.), которые другие системы добавляют через
/// [DebugOverlayController.setLine].
///
/// Вызывающий код обязан исключать его из release-сборки (см. проверку
/// [kDebugMode] в main.dart) — игрокам показываться не должен.
class DebugOverlayController extends ChangeNotifier {
  final _lines = SplayTreeMap<String, String>();
  bool _visible = false;

  bool get visible => _visible;
  set visible(bool value) {
    if (_visible == value) return;
    _visible = value;
    notifyListeners();
  }

  void setLine(String key, String value) {
    _lines[key] = value;
    // Coordinates are sampled each frame; repaint only on the overlay's
    // half-second refresh, not on every simulation tick.
  }

  void removeLine(String key) {
    _lines.remove(key);
    notifyListeners();
  }

  Map<String, String> get lines => Map.unmodifiable(_lines);
}

class FpsOverlay extends StatefulWidget {
  const FpsOverlay({super.key, required this.controller, required this.child});

  final DebugOverlayController controller;
  final Widget child;

  @override
  State<FpsOverlay> createState() => _FpsOverlayState();
}

/// Сколько последних кадров усредняем. ~2 секунды при 30 FPS: мгновенное
/// значение скачет так, что по нему нельзя принимать решения (ровно на этом
/// оверлей раньше и врал — показывал 20 FPS там, где играется как 5).
const int _windowFrames = 60;

class _FpsOverlayState extends State<FpsOverlay> {
  final List<FrameTiming> _recent = [];
  Timer? _refresh;
  double _fps = 0;
  double _frameMs = 0;
  double _uiMs = 0;
  double _rasterMs = 0;
  double _p95Ms = 0, _latencyMs = 0;

  @override
  void initState() {
    super.initState();
    // Cadence uses timestamps of rendered frames. totalSpan measures
    // pipeline latency and can overlap several displayed frames.
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    // Перерисовываем текст раз в полсекунды, а не на каждый кадр: setState
    // покадрово сам грузил бы UI-поток, то есть инструмент искажал бы то,
    // что измеряет.
    _refresh = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _recompute(),
    );
    widget.controller.addListener(_onDebugLinesChanged);
  }

  void _onTimings(List<FrameTiming> timings) {
    _recent.addAll(timings);
    if (_recent.length > _windowFrames) {
      _recent.removeRange(0, _recent.length - _windowFrames);
    }
  }

  void _recompute() {
    if (!mounted || _recent.isEmpty) return;
    final metrics = measureFrames(
      _recent
          .map((t) => t.timestampInMicroseconds(FramePhase.vsyncStart))
          .toList(),
      _recent.map((t) => t.totalSpan.inMicroseconds).toList(),
    );
    var ui = 0.0;
    var raster = 0.0;
    for (final timing in _recent) {
      ui += timing.buildDuration.inMicroseconds / 1000.0;
      raster += timing.rasterDuration.inMicroseconds / 1000.0;
    }
    final count = _recent.length;
    setState(() {
      _frameMs = metrics.intervalMs;
      _p95Ms = metrics.p95Ms;
      _latencyMs = metrics.latencyMs;
      _uiMs = ui / count;
      _rasterMs = raster / count;
      _fps = metrics.fps;
    });
  }

  void _onDebugLinesChanged() => setState(() {});

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _refresh?.cancel();
    widget.controller.removeListener(_onDebugLinesChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // Над джойстиком, а не сверху: верхний левый угол занят радаром
        // (ландшафт) и компасом (портрет).
        if (widget.controller.visible)
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 200,
            left: MediaQuery.of(context).padding.left + 8,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(8),
                color: const Color(0xAA000000),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: Color(0xFF00FF66),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'FPS: ${_fps.toStringAsFixed(0)}  '
                        '(${_frameMs.toStringAsFixed(1)} ms avg)',
                      ),
                      Text(
                        'p95 ${_p95Ms.toStringAsFixed(1)} ms  latency ${_latencyMs.toStringAsFixed(1)} ms',
                      ),
                      // Разбивка по потокам — то, ради чего обычно открывают
                      // DevTools: какой из двух за бюджетом, тот и чиним.
                      Text(
                        'ui: ${_uiMs.toStringAsFixed(1)}  '
                        'raster: ${_rasterMs.toStringAsFixed(1)}',
                      ),
                      for (final entry in widget.controller.lines.entries)
                        Text('${entry.key}: ${entry.value}'),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
