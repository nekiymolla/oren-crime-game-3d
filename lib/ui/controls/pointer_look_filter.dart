import 'dart:math' as math;
import 'dart:ui';

/// Accumulate device events, then ease their displacement across display frames.
/// Keeps the total turn independent of event rate without adding mouse inertia.
class PointerLookFilter {
  PointerLookFilter({this.sensitivity = .75, this.responseSeconds = .02});
  final double sensitivity, responseSeconds;
  Offset _pending = Offset.zero;
  void add(Offset delta) {
    if (delta.dx.isFinite && delta.dy.isFinite) _pending += delta * sensitivity;
  }

  Offset step(double seconds) {
    if (seconds <= 0 || !seconds.isFinite) return Offset.zero;
    final result = _pending * (1 - math.exp(-seconds / responseSeconds));
    _pending -= result;
    if (_pending.distanceSquared < 1e-8) _pending = Offset.zero;
    return result;
  }

  void clear() => _pending = Offset.zero;
}
