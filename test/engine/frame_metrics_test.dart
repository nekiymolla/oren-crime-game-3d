import 'package:flutter_test/flutter_test.dart';
import 'package:crime_oren/engine/debug/frame_metrics.dart';

void main() {
  test('pipeline latency does not halve an otherwise 60 Hz frame cadence', () {
    final m = measureFrames(
      [0, 16667, 33334, 50001],
      [32000, 32000, 32000, 32000],
    );
    expect(m.fps, closeTo(60, .01));
    expect(m.latencyMs, 32);
    expect(m.intervalMs, closeTo(16.667, .001));
  });
  test('frame stalls appear in cadence and p95', () {
    final m = measureFrames(
      [0, 16667, 33334, 133334],
      [10000, 10000, 10000, 10000],
    );
    expect(m.p95Ms, 100);
    expect(m.fps, closeTo(22.5, .01));
    expect(measureFrames([], []).fps, 0);
  });
}
