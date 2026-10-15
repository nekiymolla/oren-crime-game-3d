import 'dart:async';
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

  @override
  void initState() {
    super.initState();
    // addTimingsCallback — единственный честный источник: даёт РЕАЛЬНОЕ время
    // кадра с разбивкой на UI и raster. Прошлая версия считала дельту между
    // тиками планировщика, а это не то же самое: когда сцена упирается в GPU,
    // UI-поток продолжает бежать вперёд по конвейеру, и дельта тиков
    // показывает бодрые цифры, пока на экране слайдшоу. Android-овский
    // dumpsys gfxinfo тут тоже не помощник — Flutter с Impeller рисует мимо
    // HWUI, и gfxinfo видит ноль кадров.
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    // Перерисовываем текст раз в полсекунды, а не на каждый кадр: setState
    // покадрово сам грузил бы UI-поток, то есть инструмент искажал бы то,
    // что измеряет.
    _refresh = Timer.periodic(const Duration(milliseconds: 500), (_) => _recompute());
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
    var total = 0.0;
    var ui = 0.0;
    var raster = 0.0;
    for (final timing in _recent) {
      total += timing.totalSpan.inMicroseconds / 1000.0;
      ui += timing.buildDuration.inMicroseconds / 1000.0;
      raster += timing.rasterDuration.inMicroseconds / 1000.0;
    }
    final count = _recent.length;
    setState(() {
      _frameMs = total / count;
      _uiMs = ui / count;
      _rasterMs = raster / count;
      _fps = _frameMs > 0 ? 1000.0 / _frameMs : 0;
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
                    Text('FPS: ${_fps.toStringAsFixed(0)}  '
                        '(${_frameMs.toStringAsFixed(1)} ms avg)'),
                    // Разбивка по потокам — то, ради чего обычно открывают
                    // DevTools: какой из двух за бюджетом, тот и чиним.
                    Text('ui: ${_uiMs.toStringAsFixed(1)}  '
                        'raster: ${_rasterMs.toStringAsFixed(1)}'),
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
