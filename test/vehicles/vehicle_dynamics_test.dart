import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:crime_oren/vehicles/vehicle_dynamics.dart';

class Run {
  final dynamics = VehicleDynamics();
  final velocity = vm.Vector2.zero();
  double heading = 0, distance = 0;
  void step(
    double dt, {
    double throttle = 0,
    double steer = 0,
    bool handbrake = false,
  }) {
    heading = dynamics.integrate(
      dt: dt,
      velocity: velocity,
      heading: heading,
      steering: steer,
      throttle: throttle,
      handbrake: handbrake,
      mass: 1450,
      wheelbase: 2.65,
      maxSpeed: 55,
      reverseMaxSpeed: 12,
      acceleration: 5.2,
      braking: 9.6,
      drag: .32,
    );
    distance += velocity.length * dt;
  }
}

void main() {
  test(
    'acceleration is progressive and braking has a measurable stopping distance',
    () {
      final run = Run();
      for (var i = 0; i < 1200; i++) {
        run.step(1 / 120, throttle: 1);
      }
      expect(run.velocity.length, inInclusiveRange(25, 40));
      run.velocity.setValues(0, 27.78);
      run.distance = 0;
      for (var i = 0; i < 600 && run.velocity.length > .2; i++) {
        run.step(1 / 120, throttle: -1);
      }
      expect(run.distance, inInclusiveRange(30, 50));
    },
  );
  test('mirror steering produces mirror trajectories and yaw inertia', () {
    final left = Run()..velocity.setValues(0, 20);
    final right = Run()..velocity.setValues(0, 20);
    right.step(1 / 120, steer: .08);
    expect(right.dynamics.yawRate, inInclusiveRange(0.001, .1));
    final initialYaw = right.dynamics.yawRate;
    left.step(1 / 120, steer: -.08);
    for (var i = 0; i < 240; i++) {
      left.step(1 / 120, steer: -.08);
      right.step(1 / 120, steer: .08);
    }
    expect(left.heading, closeTo(-right.heading, .001));
    expect(left.velocity.x, closeTo(-right.velocity.x, .001));
    expect(right.dynamics.yawRate, greaterThan(initialYaw));
  });
  test('handbrake breaks rear grip and produces controllable oversteer', () {
    final normal = Run()..velocity.setValues(0, 20);
    final drift = Run()..velocity.setValues(0, 20);
    for (var i = 0; i < 120; i++) {
      normal.step(1 / 120, steer: .12);
      drift.step(1 / 120, steer: .12, handbrake: true);
    }
    expect(drift.heading.abs(), greaterThan(normal.heading.abs() * 1.15));
    for (var i = 0; i < 600; i++) {
      drift.step(1 / 120);
    }
    expect(drift.velocity.length, lessThan(30));
    expect(drift.dynamics.yawRate.abs(), lessThan(.05));
  });
  test('a stopped car does not turn, reverse steering turns the other way', () {
    final run = Run();
    for (var i = 0; i < 120; i++) {
      run.step(1 / 120, steer: .4);
    }
    expect(run.heading, 0);
    for (var i = 0; i < 240; i++) {
      run.step(1 / 120, steer: .3, throttle: -1);
    }
    expect(run.heading, lessThan(0));
    expect(run.velocity.length, lessThanOrEqualTo(12));
  });
  test('handling is stable across 60 and 120 Hz', () {
    final a = Run()..velocity.setValues(0, 15),
        b = Run()..velocity.setValues(0, 15);
    for (var i = 0; i < 240; i++) {
      a.step(1 / 60, steer: .06, throttle: .2);
    }
    for (var i = 0; i < 480; i++) {
      b.step(1 / 120, steer: .06, throttle: .2);
    }
    expect(a.heading, closeTo(b.heading, .05));
    expect((a.velocity - b.velocity).length, lessThan(.5));
    expect(a.dynamics.bodyRoll.abs(), inExclusiveRange(0, .2));
  });
  test('extreme input stays finite for a long drive', () {
    final run = Run();
    for (var i = 0; i < 120 * 90; i++) {
      run.step(
        1 / 120,
        throttle: 1,
        steer: .4 * math.sin(i / 120),
        handbrake: i % 300 < 45,
      );
      expect(run.velocity.length.isFinite, isTrue);
      expect(run.velocity.length, lessThan(60));
      expect(run.heading.isFinite, isTrue);
    }
  });
}
