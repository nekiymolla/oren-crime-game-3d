import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:crime_oren/vehicles/vehicle_impact.dart';

void main() {
  test('frontal wall hit rebounds rather than forcing speed to zero', () {
    final r = resolveVehicleImpact(
      velocity: vm.Vector2(0, 20),
      yawRate: 0,
      mass: 1500,
      inertia: 4000,
      arm: vm.Vector2(0, 2),
      normal: vm.Vector2(0, -1),
    );
    expect(r.velocity.y, closeTo(-2.4, 1e-5));
    expect(r.yawRate, closeTo(0, 1e-5));
    expect(r.closingSpeed, 20);
  });
  test('grazing a wall preserves most tangential momentum', () {
    final r = resolveVehicleImpact(
      velocity: vm.Vector2(20, 3),
      yawRate: 0,
      mass: 1500,
      inertia: 4000,
      arm: vm.Vector2.zero(),
      normal: vm.Vector2(0, -1),
    );
    expect(r.velocity.x, greaterThan(18));
    expect(r.velocity.y, lessThan(0));
  });
  test(
    'equal cars exchange momentum; the other car is not a concrete wall',
    () {
      final r = resolveVehicleImpact(
        velocity: vm.Vector2(0, 15),
        yawRate: 0,
        mass: 1500,
        inertia: 4000,
        arm: vm.Vector2.zero(),
        normal: vm.Vector2(0, -1),
        otherMass: 1500,
        otherVelocity: vm.Vector2.zero(),
      );
      final other = -r.impulse / 1500;
      expect(r.velocity.y, inInclusiveRange(6, 8));
      expect(other.y, greaterThan(7));
      expect((r.velocity + other).y, closeTo(15, 1e-5));
    },
  );
  test('off-centre two-body collisions dissipate energy and generate yaw', () {
    final random = math.Random(42);
    for (var i = 0; i < 500; i++) {
      final v = vm.Vector2(
            random.nextDouble() * 10,
            10 + random.nextDouble() * 20,
          ),
          other = vm.Vector2(0, random.nextDouble() * 5);
      final arm = vm.Vector2(.2 + random.nextDouble(), 2),
          otherArm = vm.Vector2(-.6, -2);
      final r = resolveVehicleImpact(
        velocity: v,
        yawRate: 0,
        mass: 1500,
        inertia: 4000,
        arm: arm,
        normal: vm.Vector2(0, -1),
        otherMass: 1200,
        otherVelocity: other,
        otherInertia: 3000,
        otherArm: otherArm,
      );
      final otherAfter = other - r.impulse / 1200;
      final otherYaw =
          -(otherArm.y * r.impulse.x - otherArm.x * r.impulse.y) / 3000;
      final before = 1500 * v.length2 / 2 + 1200 * other.length2 / 2;
      final after =
          1500 * r.velocity.length2 / 2 +
          4000 * r.yawRate * r.yawRate / 2 +
          1200 * otherAfter.length2 / 2 +
          3000 * otherYaw * otherYaw / 2;
      expect(after, lessThanOrEqualTo(before + 1));
      expect(r.yawRate.isFinite, true);
      expect(
        (r.velocity * 1500 + otherAfter * 1200 - (v * 1500 + other * 1200))
            .length,
        lessThan(.02),
      );
    }
  });
  test('separating contacts receive no extra impulse', () {
    final r = resolveVehicleImpact(
      velocity: vm.Vector2(0, -2),
      yawRate: 0,
      mass: 1500,
      inertia: 4000,
      arm: vm.Vector2(0, 2),
      normal: vm.Vector2(0, -1),
    );
    expect(r.impulse.length, 0);
    expect(r.velocity.y, -2);
  });
}
