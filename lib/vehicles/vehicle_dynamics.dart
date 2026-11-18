import 'dart:math' as math;
import 'package:vector_math/vector_math.dart' as vm;

/// Planar two-axle tyre model. Forces saturate at available axle grip;
/// yaw has inertia rather than following the steering wheel instantly.
/// Vertical wheel contact is supplied separately by the terrain sampler.
class VehicleDynamics {
  double yawRate = 0;
  double longitudinalAcceleration = 0;
  double lateralAcceleration = 0;
  double bodyPitch = 0, bodyRoll = 0;
  double _pitchVelocity = 0, _rollVelocity = 0;

  double integrate({
    required double dt,
    required vm.Vector2 velocity,
    required double heading,
    required double steering,
    required double throttle,
    required bool handbrake,
    required double mass,
    required double wheelbase,
    required double maxSpeed,
    required double reverseMaxSpeed,
    required double acceleration,
    required double braking,
    required double drag,
    double tyreFriction = 1.0,
    double frontStiffness = 40,
    double rearStiffness = 58,
    double stabilityAssist = 1.2,
    double driveBias = .35,
    double rollCompliance = .009,
    double pitchCompliance = .007,
    double suspensionDamping = 11,
  }) {
    final forward = vm.Vector2(math.sin(heading), math.cos(heading));
    final right = vm.Vector2(forward.y, -forward.x);
    var longitudinal = velocity.dot(forward);
    var lateral = velocity.dot(right);
    var ax = 0.0;
    if (throttle > 0) {
      if (longitudinal < -0.15) {
        ax = braking * throttle;
      } else {
        final ratio = (longitudinal.abs() / maxSpeed).clamp(0.0, 1.0);
        ax = acceleration * throttle * (1 - math.pow(ratio, 1.5));
      }
    } else if (throttle < 0) {
      if (longitudinal > 0.15) {
        ax = braking * throttle;
      } else {
        ax =
            acceleration *
            .48 *
            throttle *
            (1 - (longitudinal.abs() / reverseMaxSpeed).clamp(0.0, 1.0));
      }
    }
    final resistance = drag + .0018 * longitudinal * longitudinal;
    if (longitudinal.abs() > .01) ax -= resistance * longitudinal.sign;
    if (handbrake && longitudinal.abs() > .01) ax -= 4.5 * longitudinal.sign;
    // A braking step must not numerically reverse a rolling car.
    final was = longitudinal;
    longitudinal += ax * dt;
    if (was.abs() > .15 && was * longitudinal < 0 && throttle * was < 0) {
      longitudinal = 0;
    }
    if (throttle.abs() < .01 && was * longitudinal < 0) longitudinal = 0;
    longitudinal = longitudinal.clamp(-reverseMaxSpeed, maxSpeed);
    longitudinalAcceleration = (longitudinal - was) / dt;

    final speed = longitudinal.abs();
    final a = wheelbase * .45, b = wheelbase - a;
    final dynamicBlend = ((speed - 2) / 3).clamp(0.0, 1.0);
    final frontShare =
        (.55 - longitudinalAcceleration * .52 / (9.81 * wheelbase)).clamp(
          .25,
          .8,
        );
    final grip = mass * 9.81 * tyreFriction;
    final frontGrip = grip * frontShare;
    final rearGrip = grip * (1 - frontShare) * (handbrake ? .28 : 1);
    final slipFront =
        steering * (longitudinal < 0 ? -1 : 1) -
        math.atan2(lateral + a * yawRate, math.max(speed, 2));
    final slipRear = -math.atan2(lateral - b * yawRate, math.max(speed, 2));
    double tyreForce(double slip, double load, double stiffness) {
      final x = (slip * stiffness / math.max(load, 1)).clamp(-10.0, 10.0);
      final e = math.exp(2 * x);
      return load * (e - 1) / (e + 1);
    }

    // Longitudinal braking also consumes grip (a friction circle).
    final brakingGrip = longitudinalAcceleration * longitudinal < 0;
    final frontDrive = brakingGrip ? frontShare : driveBias;
    double remainingGrip(double axleLoad, double share) {
      final demand =
          (mass *
                  longitudinalAcceleration.abs() *
                  share /
                  math.max(1, axleLoad))
              .clamp(0.0, .98);
      return math.sqrt(math.max(.08, 1 - demand * demand));
    }

    final frontFraction = remainingGrip(frontGrip, frontDrive);
    final rearFraction = remainingGrip(rearGrip, 1 - frontDrive);
    final frontForce = tyreForce(
      slipFront,
      frontGrip * frontFraction,
      mass * frontStiffness,
    );
    final rearForce = tyreForce(
      slipRear,
      rearGrip * rearFraction,
      mass * rearStiffness,
    );
    final frontLateral = frontForce * math.cos(steering);
    final ay = (frontLateral + rearForce) / mass;
    longitudinal -= frontForce * math.sin(steering) / mass * dt;
    final inertia = mass * wheelbase * wheelbase * .40;
    final dynamicYaw =
        yawRate + (a * frontLateral - b * rearForce) / inertia * dt;
    final parkingYaw = longitudinal / wheelbase * math.tan(steering);
    yawRate = parkingYaw * (1 - dynamicBlend) + dynamicYaw * dynamicBlend;
    if (speed < .08) yawRate = 0;
    if (!handbrake && speed > 5) {
      final goal = (longitudinal / wheelbase * math.tan(steering)).clamp(
        -9.81 * tyreFriction / math.max(speed, 1),
        9.81 * tyreFriction / math.max(speed, 1),
      );
      yawRate += (goal - yawRate) * (1 - math.exp(-stabilityAssist * dt));
    }
    heading += yawRate * dt;
    lateral += ay * dt;
    final newForward = vm.Vector2(math.sin(heading), math.cos(heading));
    // Integrate forces in the world frame. Rotating an unchanged local
    // longitudinal speed with the body would inject energy during a spin.
    final physicalVelocity = forward * longitudinal + right * lateral;
    velocity.setFrom(
      newForward * longitudinal * (1 - dynamicBlend) +
          physicalVelocity * dynamicBlend,
    );
    lateralAcceleration = speed < 5 ? yawRate * longitudinal : ay;

    final targetPitch = (-longitudinalAcceleration * pitchCompliance).clamp(
      -.09,
      .09,
    );
    final targetRoll = (lateralAcceleration * rollCompliance).clamp(-.12, .12);
    _pitchVelocity +=
        (48 * (targetPitch - bodyPitch) - suspensionDamping * _pitchVelocity) *
        dt;
    _rollVelocity +=
        (42 * (targetRoll - bodyRoll) - suspensionDamping * _rollVelocity) * dt;
    bodyPitch += _pitchVelocity * dt;
    bodyRoll += _rollVelocity * dt;
    return heading;
  }

  void kickImpact(double lateralDelta, double longitudinalDelta) {
    _pitchVelocity = (_pitchVelocity + longitudinalDelta * .035).clamp(
      -1.2,
      1.2,
    );
    _rollVelocity = (_rollVelocity - lateralDelta * .035).clamp(-1.2, 1.2);
  }

  void stopYaw() {
    yawRate = 0;
  }
}
