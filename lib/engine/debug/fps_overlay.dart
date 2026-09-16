import 'dart:collection';

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

  void setLine(String key, String value) {
    _lines[key] = value;
    notifyListeners();
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

class _FpsOverlayState extends State<FpsOverlay> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  double _fps = 0;
  double _frameMs = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    widget.controller.addListener(_onDebugLinesChanged);
  }

  void _onTick(Duration elapsed) {
    final deltaMs = (elapsed - _lastTick).inMicroseconds / 1000.0;
    _lastTick = elapsed;
    if (deltaMs <= 0) return;
    setState(() {
      _frameMs = deltaMs;
      _fps = 1000.0 / deltaMs;
    });
  }

  void _onDebugLinesChanged() => setState(() {});

  @override
  void dispose() {
    _ticker.dispose();
    widget.controller.removeListener(_onDebugLinesChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
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
                    Text('FPS: ${_fps.toStringAsFixed(0)}  '
                        '(${_frameMs.toStringAsFixed(1)} ms)'),
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
