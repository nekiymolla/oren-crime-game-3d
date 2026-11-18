import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:crime_oren/vehicles/vehicle_models.dart';
import 'package:crime_oren/vehicles/vehicle_spec.dart';
import 'package:crime_oren/vehicles/vehicle_controller_component.dart';

void main() {
  final entries =
      (jsonDecode(
                File('assets/data/vehicles.json').readAsStringSync(),
              )['vehicles']
              as List)
          .cast<Map<String, dynamic>>();
  final specs = {
    for (final e in entries) e['modelId'] as String: VehicleSpec.fromJson(e),
  };
  test('every shipping model has its own complete driving profile', () {
    expect(specs.keys.toSet(), VehicleModels.ids.toSet());
    expect(entries.map((e) => e['id']).toSet().length, entries.length);
    expect(
      specs['sports2']!.maxSpeedKmh,
      greaterThan(specs['sports']!.maxSpeedKmh),
    );
    expect(
      specs['sports2']!.stabilityAssist,
      lessThan(specs['sports']!.stabilityAssist),
    );
    expect(
      specs['hatchback']!.maxSpeedKmh,
      lessThan(specs['sedan_80']!.maxSpeedKmh),
    );
    expect(
      specs['hatchback']!.maxLateralAcceleration,
      greaterThan(specs['sedan_80']!.maxLateralAcceleration),
    );
    expect(specs['suv']!.mass, greaterThan(specs['hatchback']!.mass));
  });
  VehicleControllerComponent make(VehicleSpec s) {
    final c = VehicleControllerComponent(
      maxSpeed: s.maxSpeedMs,
      acceleration: s.acceleration,
      braking: s.braking,
      mass: s.mass,
      tyreFriction: s.tyreFriction,
      maxSteerAngle: s.maxSteerAngle,
      steeringResponse: s.steeringResponse,
      maxLateralAcceleration: s.maxLateralAcceleration,
      frontStiffness: s.frontStiffness,
      rearStiffness: s.rearStiffness,
      stabilityAssist: s.stabilityAssist,
      driveBias: s.driveBias,
    );
    Node().addComponent(c);
    c.obstacleRaycast = (_, _, _) => null;
    return c;
  }

  test(
    'the starter sedan remains aligned under a full 90 km/h steering input',
    () {
      final c = make(specs['sedan_80']!)..velocityXZ.setValues(0, 25);
      c.setInput(throttle: .4, steer: 1);
      for (var i = 0; i < 120; i++) {
        c.fixedUpdate(1 / 60);
      }
      final forward = vm.Vector2(math.sin(c.heading), math.cos(c.heading));
      expect(c.velocityXZ.normalized().dot(forward), greaterThan(.94));
      expect(c.dynamics.yawRate.abs(), lessThan(.6));
      c.setInput(throttle: 0, steer: 0);
      for (var i = 0; i < 180; i++) {
        c.fixedUpdate(1 / 60);
      }
      expect(c.dynamics.yawRate.abs(), lessThan(.04));
    },
  );
  test(
    'distinct profiles produce different acceleration and steering authority',
    () {
      final compact = make(specs['hatchback']!), sport = make(specs['sports']!);
      for (final c in [compact, sport]) {
        c.setInput(throttle: 1, steer: 0);
        for (var i = 0; i < 300; i++) {
          c.fixedUpdate(1 / 60);
        }
      }
      expect(sport.speed, greaterThan(compact.speed * 1.4));
      compact.velocityXZ.setValues(0, 25);
      sport.velocityXZ.setValues(0, 25);
      for (final c in [compact, sport]) {
        c.setInput(throttle: 0, steer: 1);
        for (var i = 0; i < 120; i++) {
          c.fixedUpdate(1 / 60);
        }
      }
      expect(
        sport.steeringAngle.abs(),
        greaterThan(compact.steeringAngle.abs()),
      );
    },
  );
}
