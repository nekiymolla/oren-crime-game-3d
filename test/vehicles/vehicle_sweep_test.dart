import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:crime_oren/player/character_motion.dart';
import 'package:crime_oren/vehicles/vehicle_sweep.dart';

CharacterRaycaster wall(double x) => (origin, direction, reach) {
  if (direction.x <= 0 || origin.x > x) return null;
  final distance = (x - origin.x) / direction.x;
  return distance <= reach
      ? CharacterRayHit(distance: distance, normal: vm.Vector3(-1, 0, 0))
      : null;
};
void main() {
  VehicleSweepHit? sweep(
    vm.Vector3 move,
    double yaw,
    CharacterRaycaster cast,
  ) => sweepVehicleHull(
    position: vm.Vector3.zero(),
    displacement: move,
    oldHeading: 0,
    newHeading: yaw,
    halfWidth: 1,
    halfLength: 2,
    probeHeight: .5,
    cast: cast,
  );
  test(
    'sideways drift is stopped by the leading side, not the front bumper',
    () {
      final hit = sweep(vm.Vector3(3, 0, 0), 0, wall(2));
      expect(hit, isNotNull);
      expect(hit!.fraction, closeTo((1 - .025) / 3, .00001));
      expect(hit.normal.x, -1);
    },
  );
  test('turning corner cannot swing into a wall with a stationary centre', () {
    final hit = sweep(vm.Vector3.zero(), .2, wall(1.1));
    expect(hit, isNotNull);
    expect(hit!.fraction, inExclusiveRange(0, 1));
  });
  test('movement parallel to a wall remains unobstructed', () {
    expect(sweep(vm.Vector3(0, 0, 10), 0, wall(1.1)), isNull);
  });
  test('high-speed displacement cannot tunnel through a thin wall', () {
    final hit = sweep(vm.Vector3(20, 0, 0), 0, wall(5));
    expect(hit!.fraction, lessThan(.2));
    final cornerX = 1 + 20 * hit.fraction;
    expect(cornerX, lessThan(5));
  });
}
