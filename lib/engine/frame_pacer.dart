/// Budgeted 60 Hz rendering on 60/90/120/144 Hz displays. Phase allowance
/// tolerates ProMotion jitter; a missed deadline never creates burst renders.
class FramePacer {
  FramePacer({this.framesPerSecond = 60});
  final int framesPerSecond;
  int? _lastVsync, _lastRender;
  double _credit = 0;
  double? advance(int timestampMicros) {
    final period = 1000000 / framesPerSecond;
    final vsync = _lastVsync, render = _lastRender;
    _lastVsync = timestampMicros;
    if (vsync == null || render == null) {
      _lastRender = timestampMicros;
      return period / 1000000;
    }
    _credit += timestampMicros - vsync;
    if (_credit < period - 2500 || timestampMicros - render < period * .55) {
      return null;
    }
    _credit -= period;
    if (_credit > period) _credit = 0;
    _lastRender = timestampMicros;
    return (timestampMicros - render) / 1000000;
  }

  void reset() {
    _lastVsync = _lastRender = null;
    _credit = 0;
  }
}
