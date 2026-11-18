import 'package:flutter_test/flutter_test.dart';
import 'package:crime_oren/engine/frame_pacer.dart';

void main() {
  test('60/90/120/144 Hz displays all produce 60 scene frames per second', () {
    for (final rate in [60, 90, 120, 144]) {
      final pacer = FramePacer();
      var count = 0;
      var total = 0.0;
      for (var i = 0; i < rate * 10; i++) {
        final dt = pacer.advance((i * 1000000 / rate).round());
        if (dt != null) {
          count++;
          total += dt;
        }
      }
      expect(count, inInclusiveRange(599, 601));
      expect(total, closeTo(10, .03));
    }
  });
  test('a stall skips obsolete deadlines without burst renders', () {
    final p = FramePacer();
    p.advance(0);
    expect(p.advance(100000), closeTo(.1, 1e-9));
    expect(p.advance(100001), isNull);
    p.reset();
    expect(p.advance(500000), closeTo(1 / 60, 1e-9));
  });
  test('ProMotion phase jitter does not turn 60 usable ticks into 30', () {
    final p = FramePacer();
    var count = 0;
    for (var i = 0; i < 600; i++) {
      final jitter = i.isEven ? 700 : -700;
      if (p.advance((i * 1000000 / 60).round() + jitter) != null) count++;
    }
    expect(count, inInclusiveRange(599, 601));
  });
}
