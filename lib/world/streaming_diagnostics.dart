import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show kDebugMode;

/// Bounded debug timings. Async durations include waiting and frame yields;
/// only synchronous stages measure a contiguous block of main-isolate work.
class StreamingDiagnostics {
  static final _samples = Queue<Map<String, Object>>();
  static List<Map<String, Object>> get samples => _samples.toList();
  static String get json => jsonEncode(samples);
  static void clear() => _samples.clear();

  static void _record(
    String chunk,
    String stage,
    int start,
    int elapsed,
    bool async,
  ) {
    _samples.add({
      'chunk': chunk,
      'stage': stage,
      'startUs': start,
      'elapsedUs': elapsed,
      'async': async,
    });
    while (_samples.length > 512) {
      _samples.removeFirst();
    }
  }

  static T sync<T>(String chunk, String stage, T Function() work) {
    if (!kDebugMode) return work();
    final start = developer.Timeline.now;
    try {
      return developer.Timeline.timeSync(
        'stream.$stage',
        work,
        arguments: {'chunk': chunk},
      );
    } finally {
      _record(chunk, stage, start, developer.Timeline.now - start, false);
    }
  }

  static Future<T> async<T>(
    String chunk,
    String stage,
    Future<T> Function() work,
  ) async {
    if (!kDebugMode) return work();
    final start = developer.Timeline.now;
    final task = developer.TimelineTask()
      ..start('stream.$stage', arguments: {'chunk': chunk});
    try {
      return await work();
    } finally {
      task.finish();
      _record(chunk, stage, start, developer.Timeline.now - start, true);
    }
  }
}
