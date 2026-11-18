/// Rendered-frame cadence and pipeline latency are different measurements.
/// Two overlapped 30 ms frames can still be delivered 16.7 ms apart.
class FrameMetrics {
  const FrameMetrics(this.fps, this.intervalMs, this.p95Ms, this.latencyMs);
  final double fps, intervalMs, p95Ms, latencyMs;
}

FrameMetrics measureFrames(List<int> vsyncMicros, List<int> latencyMicros) {
  final gaps = <double>[];
  for (var i = 1; i < vsyncMicros.length; i++) {
    final gap = vsyncMicros[i] - vsyncMicros[i - 1];
    if (gap > 0) gaps.add(gap / 1000);
  }
  final latency = latencyMicros.isEmpty
      ? 0.0
      : latencyMicros.fold<int>(0, (a, b) => a + b) /
            latencyMicros.length /
            1000;
  if (gaps.isEmpty) return FrameMetrics(0, 0, 0, latency);
  final average = gaps.reduce((a, b) => a + b) / gaps.length;
  gaps.sort();
  return FrameMetrics(
    1000 / average,
    average,
    gaps[((gaps.length - 1) * .95).ceil()],
    latency,
  );
}
