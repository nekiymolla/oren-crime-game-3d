import 'dart:async';
import 'dart:collection';

/// Serialises expensive scene imports and yields to rendering between jobs.
/// Repeated requests for the same key share their completion future.
class StreamingWork<T> {
  StreamingWork({Future<void> Function()? yieldToFrame})
    : _yieldToFrame =
          yieldToFrame ?? (() => Future<void>.delayed(Duration.zero));

  final Future<void> Function() _yieldToFrame;
  final Queue<(String, Future<T> Function(), Completer<T>)> _waiting = Queue();
  final Map<String, Future<T>> _requests = {};
  bool _running = false;
  int get pendingCount => _requests.length;

  Future<T> schedule(String key, Future<T> Function() load) {
    final existing = _requests[key];
    if (existing != null) return existing;
    final completion = Completer<T>();
    _requests[key] = completion.future;
    _waiting.add((key, load, completion));
    _pump();
    return completion.future;
  }

  void _pump() {
    if (_running || _waiting.isEmpty) return;
    _running = true;
    final (key, load, completion) = _waiting.removeFirst();
    Future<void>(() async {
      try {
        completion.complete(await load());
      } catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        _requests.remove(key);
        try {
          if (_waiting.isNotEmpty) await _yieldToFrame();
        } finally {
          _running = false;
          _pump();
        }
      }
    });
  }
}

/// Small boundary hysteresis prevents reimporting an entire row when a player
/// oscillates across a grid line. Teleports still select their new cell at once.
class StreamingCenter {
  StreamingCenter({required this.cellSize, this.margin = 20});
  final double cellSize, margin;
  (int, int)? _cell;
  (int, int) get cell => _cell!;
  void reset() => _cell = null;

  bool update(double x, double z) {
    int axis(double value, int? previous) {
      if (previous != null &&
          value >= previous * cellSize - margin &&
          value < (previous + 1) * cellSize + margin) {
        return previous;
      }
      return (value / cellSize).floor();
    }

    final next = (axis(x, _cell?.$1), axis(z, _cell?.$2));
    if (next == _cell) return false;
    _cell = next;
    return true;
  }
}

/// Keeps material preparation inside the streaming job and limits the amount
/// resumed in one frame, even if all asset futures complete immediately.
class FramePreparation {
  FramePreparation({
    required this.yieldToFrame,
    this.maxItems = 4,
    this.budget = const Duration(milliseconds: 2),
  });
  final Future<void> Function() yieldToFrame;
  final int maxItems;
  final Duration budget;

  Future<void> run<T>(
    Iterable<T> items,
    Future<void> Function(T) prepare, {
    bool Function()? isCurrent,
  }) async {
    final pending = items.iterator;
    final watch = Stopwatch()..start();
    var count = 0;
    while (pending.moveNext()) {
      if (isCurrent?.call() == false) return;
      if (count >= maxItems || (count > 0 && watch.elapsed >= budget)) {
        await yieldToFrame();
        if (isCurrent?.call() == false) return;
        count = 0;
        watch.reset();
      }
      await prepare(pending.current);
      count++;
    }
  }
}
