import 'package:vector_math/vector_math.dart' as vm;

/// A short rigid-body impact. A stationary wall has infinite mass. The solver
/// preserves tangential momentum instead of applying a per-frame speed cut.
class ImpactResponse {
  const ImpactResponse(
    this.velocity,
    this.yawRate,
    this.impulse,
    this.closingSpeed,
  );
  final vm.Vector2 velocity, impulse;
  final double yawRate, closingSpeed;
}

class VehicleContactBody {
  VehicleContactBody({
    required this.mass,
    required this.velocity,
    required this.applyImpulse,
    this.inertia = double.infinity,
    this.yawRate = 0,
    vm.Vector2? arm,
  }) : arm = arm ?? vm.Vector2.zero();
  final double mass, inertia, yawRate;
  final vm.Vector2 arm;
  final vm.Vector2 velocity;
  final void Function(vm.Vector2 impulse, vm.Vector3 point) applyImpulse;
}

class VehicleImpact {
  VehicleImpact({
    required this.point,
    required this.normal,
    required this.closingSpeed,
    required this.impulse,
    this.localPoint,
    this.localNormal,
  });
  final vm.Vector3? localPoint, localNormal;
  final vm.Vector3 point, normal;
  final double closingSpeed, impulse;
}

ImpactResponse resolveVehicleImpact({
  required vm.Vector2 velocity,
  required double yawRate,
  required double mass,
  required double inertia,
  required vm.Vector2 arm,
  required vm.Vector2 normal,
  double otherMass = double.infinity,
  vm.Vector2? otherVelocity,
  double otherInertia = double.infinity,
  double otherYawRate = 0,
  vm.Vector2? otherArm,
  double restitution = .12,
  double friction = .26,
}) {
  final n = normal.normalized();
  final other = otherVelocity ?? vm.Vector2.zero();
  final rOther = otherArm ?? vm.Vector2.zero();
  final contactVelocity =
      velocity +
      vm.Vector2(yawRate * arm.y, -yawRate * arm.x) -
      other -
      vm.Vector2(otherYawRate * rOther.y, -otherYawRate * rOther.x);
  final vn = contactVelocity.dot(n);
  if (vn >= 0) {
    return ImpactResponse(velocity.clone(), yawRate, vm.Vector2.zero(), 0);
  }
  double torque(vm.Vector2 d) => arm.y * d.x - arm.x * d.y;
  final inverseMass = 1 / mass + (otherMass.isFinite ? 1 / otherMass : 0);
  final rn = torque(n);
  final rnOther = rOther.y * n.x - rOther.x * n.y;
  final invOtherInertia = otherInertia.isFinite ? 1 / otherInertia : 0.0;
  final e = -vn < .8 ? 0.0 : restitution;
  final j =
      -(1 + e) *
      vn /
      (inverseMass + rn * rn / inertia + rnOther * rnOther * invOtherInertia);
  final impulse = n * j;
  var result = velocity + impulse / mass;
  var yaw = yawRate + rn * j / inertia;
  final tangent = vm.Vector2(-n.y, n.x), rt = torque(tangent);
  final otherYawAfter = otherYawRate - rnOther * j * invOtherInertia;
  final otherAfter =
      other - (otherMass.isFinite ? impulse / otherMass : vm.Vector2.zero());
  final vt =
      (result +
              vm.Vector2(yaw * arm.y, -yaw * arm.x) -
              otherAfter -
              vm.Vector2(otherYawAfter * rOther.y, -otherYawAfter * rOther.x))
          .dot(tangent);
  final rtOther = rOther.y * tangent.x - rOther.x * tangent.y;
  final jt =
      (-vt /
              (inverseMass +
                  rt * rt / inertia +
                  rtOther * rtOther * invOtherInertia))
          .clamp(-friction * j, friction * j);
  impulse.addScaled(tangent, jt);
  result.addScaled(tangent, jt / mass);
  yaw += rt * jt / inertia;
  return ImpactResponse(result, yaw, impulse, -vn);
}
