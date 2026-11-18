import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:crime_oren/vehicles/vehicle_sweep.dart';

void main() {
  VehicleSweepHit? run(vm.Vector3 move, vm.Vector3 tree, {double turn = 0}) =>
      sweepVehicleCircle(
        position: vm.Vector3.zero(),
        displacement: move,
        oldHeading: 0,
        newHeading: turn,
        halfWidth: 1,
        halfLength: 2,
        circle: tree,
        radius: .28,
      );
  test('a trunk stops the actual bumper, not an inflated metre-wide cap', () {
    final hit = run(vm.Vector3(0, 0, 10), vm.Vector3(0, 0, 5))!;
    expect(hit.fraction * 10, closeTo(2.715, .012));
    expect(hit.normal.z, closeTo(-1, 1e-5));
  });
  test('corner brushes retain an angled contact normal', () {
    final hit = run(vm.Vector3(0, 0, 10), vm.Vector3(1.2, 0, 5))!;
    expect(hit.normal.x, lessThan(-.5));
    expect(hit.normal.z, lessThan(-.5));
  });
  test('a sideways strike between corner rays is caught', () {
    final hit = run(vm.Vector3(3, 0, 0), vm.Vector3(2, 0, .6))!;
    expect(hit.fraction * 3, closeTo(.715, .012));
  });
  test('a turning corner cannot pass through a trunk', () {
    expect(
      run(vm.Vector3.zero(), vm.Vector3(1.4, 0, 1.8), turn: .5),
      isNotNull,
    );
  });
  test('a separating overlap can back away and a clear gap stays clear', () {
    expect(run(vm.Vector3(0, 0, -1), vm.Vector3(0, 0, 2.1)), isNull);
    expect(run(vm.Vector3(0, 0, 10), vm.Vector3(1.4, 0, 5)), isNull);
  });
}
