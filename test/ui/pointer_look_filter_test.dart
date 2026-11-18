import 'package:flutter_test/flutter_test.dart';
import 'package:crime_oren/ui/controls/pointer_look_filter.dart';

void main() {
  test('turn distance is conserved across display refresh rates', () {
    Offset run(int hz) {
      final filter = PointerLookFilter()..add(const Offset(100, 40));
      var total = Offset.zero;
      for (var i = 0; i < hz; i++) {
        total += filter.step(1 / hz);
      }
      return total;
    }

    final at60 = run(60), at120 = run(120);
    expect(at60.dx, closeTo(75, .001));
    expect(at60.dy, closeTo(30, .001));
    expect((at120 - at60).distance, lessThan(.001));
  });
  test(
    'release drops pending motion and invalid device samples are ignored',
    () {
      final filter = PointerLookFilter()..add(const Offset(100, 0));
      final first = filter.step(1 / 60);
      expect(first.dx, greaterThan(0));
      expect(first.dx, lessThan(75));
      filter.clear();
      filter.add(Offset(double.nan, 0));
      expect(filter.step(1 / 60), Offset.zero);
    },
  );
}
