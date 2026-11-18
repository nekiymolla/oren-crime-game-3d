import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../player/character_motion.dart'
    show CharacterRaycaster, CharacterRayHit;
import 'vehicle_dynamics.dart';
import 'wheel_contact.dart';
import 'vehicle_sweep.dart';

/// Two-axle tyre forces and yaw inertia, terrain contact and sprung body.
/// This is a planar handling model with swept collision probes; it does
/// not simulate a full 3D rigid body, airborne suspension or deformation.
class VehicleControllerComponent extends Component {
  VehicleControllerComponent({
    required this.maxSpeed,
    required this.acceleration,
    required this.braking,
    double? reverseMaxSpeed,
    this.drag = 0.32,
    this.mass = 1450,
    this.tyreFriction = 1.0,
    this.maxSteerAngle = 0.55,
    this.wheelBase = 2.6,
    this.groundPlaneHeight = 0.0,
    this.gripAtLowSpeed = 14.0,
    this.gripAtHighSpeed = 4.0,
    this.driftThresholdSpeed = 9.0,
    this.bodyHalfWidth = 0.9,
    this.bodyHalfLength = 2.2,
    this.collisionProbeHeight = 0.5,
  }) : reverseMaxSpeed = reverseMaxSpeed ?? maxSpeed * 0.35;

  /// Максимальная скорость вперёд, м/с.
  double maxSpeed;

  /// Максимальная скорость назад, м/с (по умолчанию — доля от maxSpeed).
  double reverseMaxSpeed;

  /// Ускорение при газе, м/с².
  double acceleration;

  /// Замедление при торможении, м/с².
  double braking;

  /// Пассивное замедление накатом (без газа/тормоза), м/с².
  double drag;
  double mass, tyreFriction;
  final VehicleDynamics dynamics = VehicleDynamics();
  Node? sprungBody;
  List<Node> wheelNodes = const [];
  List<vm.Vector3> _wheelRest = const [];
  double suspensionTravel = .18;
  late List<vm.Vector3> contactAnchors = [
    vm.Vector3(-bodyHalfWidth * .81, 0, wheelBase / 2),
    vm.Vector3(bodyHalfWidth * .81, 0, wheelBase / 2),
    vm.Vector3(-bodyHalfWidth * .81, 0, -wheelBase / 2),
    vm.Vector3(bodyHalfWidth * .81, 0, -wheelBase / 2),
  ];
  WheelContact? groundContact;

  void configureWheels(List<Node> wheels) {
    wheelNodes = wheels;
    _wheelRest = [for (final wheel in wheels) wheel.position.clone()];
    if (wheels.length == 4) {
      contactAnchors = [for (final p in _wheelRest) p.clone()..y = 0];
    } else if (wheels.length == 3) {
      final track = (_wheelRest[0].x - _wheelRest[1].x).abs() / 2;
      contactAnchors = [
        _wheelRest[0].clone()..y = 0,
        _wheelRest[1].clone()..y = 0,
        vm.Vector3(-track, 0, _wheelRest[2].z),
        vm.Vector3(track, 0, _wheelRest[2].z),
      ];
    }
  }

  bool _handbrake = false;

  /// Максимальный угол поворота колёс, рад.
  double maxSteerAngle;

  /// Колёсная база — влияет на радиус разворота (велосипедная модель).
  double wheelBase;

  /// Заглушка вместо raycast до земли, пока нет rigid-body физики.
  double? groundPlaneHeight;
  double Function(double, double)? groundHeightAt;
  double _terrainPitch = 0, _terrainRoll = 0;
  CharacterRaycaster? obstacleRaycast;
  void Function(vm.Vector3 position)? prepareObstacles;

  /// Насколько быстро продольная скорость "прилипает" к направлению носа
  /// машины на низкой/высокой скорости — ниже значение на высокой скорости
  /// даёт занос в резких поворотах вместо мгновенного разворота вектора.
  double gripAtLowSpeed;
  double gripAtHighSpeed;

  /// Скорость, начиная с которой сцепление начинает падать к gripAtHighSpeed.
  double driftThresholdSpeed;

  /// Половина ширины/длины кузова — точки прощупывания препятствий по
  /// бамперу (3 луча: центр + оба края), чтобы ловить и лобовые, и угловые
  /// столкновения со зданиями.
  double bodyHalfWidth;
  double bodyHalfLength;

  /// Высота лучей столкновений от узла-машины (её origin — уровень земли).
  double collisionProbeHeight;

  /// Зовётся ровно в момент, когда бампер реально во что-то упёрся (не на
  /// каждый кадр) — аргумент: скорость машины (м/с) прямо перед остановкой.
  /// Используется VehicleDamageState (см. vehicle_damage.dart) для накопления
  /// визуальных повреждений — сама физика столкновений тут ни при чём,
  /// колбэк просто сообщает наружу, что произошло и насколько сильно.
  void Function(double impactSpeed)? onCollision;

  /// Extra simple obstacles not represented by raycastable scene meshes.
  double? Function(
    vm.Vector3 origin,
    vm.Vector3 direction,
    double distance,
    double radius,
  )?
  additionalObstacleSweep;

  /// Скорость машины как вектор в мировых XZ (не всегда совпадает с
  /// направлением носа — расхождение и есть занос).
  vm.Vector2 velocityXZ = vm.Vector2.zero();

  /// Курс носа машины (рад, 0 = +Z), та же конвенция yaw, что и у
  /// FollowCameraController — используется для авто-довода камеры за
  /// машиной, когда игрок не крутит вид сам (см. Game.tick). Пишется и
  /// снаружи — для машины, собранной на месте угнанной (см. Game._carjack):
  /// иначе она развернулась бы носом на +Z.
  double heading = 0.0;
  double _throttleInput = 0.0;
  double _steerInput = 0.0;
  double _steering = 0.0;

  /// Actual wheel angle, limited at speed to keep full touch input usable.
  double get steeringAngle {
    final limit = math.atan(8.0 * wheelBase / math.max(1.0, speed * speed));
    return _steering * math.min(maxSteerAngle, limit);
  }

  double get speed => velocityXZ.length;

  /// Насколько текущее движение "не туда, куда смотрит машина" — 0 = едет
  /// строго носом вперёд, ближе к 1 = боком (для UI/звука заноса позже).
  double get driftFactor {
    if (speed < 0.5) return 0.0;
    final forward = vm.Vector2(math.sin(heading), math.cos(heading));
    final align = (velocityXZ.normalized()).dot(forward).clamp(-1.0, 1.0);
    return (1.0 - align).clamp(0.0, 1.0);
  }

  void setInput({
    required double throttle,
    required double steer,
    bool handbrake = false,
  }) {
    _handbrake = handbrake;
    _throttleInput = throttle.clamp(-1.0, 1.0);
    _steerInput = steer.clamp(-1.0, 1.0);
  }

  Node get _rootNode {
    Node curr = node;
    while (curr.parent != null) {
      curr = curr.parent!;
    }
    return curr;
  }

  bool _isExcluded(Node hitNode) {
    if (hitNode == node) return true;
    Node? p = hitNode.parent;
    while (p != null) {
      if (p == node) return true;
      p = p.parent;
    }
    return false;
  }

  @override
  void update(double deltaSeconds) => fixedUpdate(deltaSeconds);

  @override
  void fixedUpdate(double fixedDt) {
    // A stalled debug frame must not teleport a car through a whole block.
    final dt = math.min(fixedDt, 0.05);
    if (dt <= 0.0 || !isAttached) return;

    final steeringRate = _steerInput.abs() < _steering.abs() ? 8.0 : 5.0;
    _steering +=
        (_steerInput - _steering) * (1.0 - math.exp(-steeringRate * dt));

    final previousHeading = heading;
    final steps = (dt / (1 / 120)).ceil();
    for (var i = 0; i < steps; i++) {
      heading = dynamics.integrate(
        dt: dt / steps,
        velocity: velocityXZ,
        heading: heading,
        steering: steeringAngle,
        throttle: _throttleInput,
        handbrake: _handbrake,
        mass: mass,
        wheelbase: wheelBase,
        maxSpeed: maxSpeed,
        reverseMaxSpeed: reverseMaxSpeed,
        acceleration: acceleration,
        braking: braking,
        drag: drag,
        tyreFriction: tyreFriction,
      );
    }
    final newForward = vm.Vector2(math.sin(heading), math.cos(heading));
    final body = sprungBody;
    if (body != null) {
      body.rotation =
          vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), dynamics.bodyPitch) *
          vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), dynamics.bodyRoll);
    }

    // 4. Столкновения: щупаем три точки бампера (центр + оба края) вдоль
    // направления движения и останавливаем машину перед препятствием вместо
    // проезда сквозь здания.
    final currentPos = (node.globalTransform * vm.Vector4(0, 0, 0, 1)).xyz;
    var moveDelta = vm.Vector3(velocityXZ.x, 0, velocityXZ.y) * dt;
    final moveDist = moveDelta.length;
    if (moveDist > 1e-5 || (heading - previousHeading).abs() > 1e-5) {
      prepareObstacles?.call(currentPos);
      CharacterRayHit? cast(
        vm.Vector3 origin,
        vm.Vector3 direction,
        double reach,
      ) {
        final custom = obstacleRaycast;
        if (custom != null) return custom(origin, direction, reach);
        final hit = raycastNode(
          _rootNode,
          vm.Ray.originDirection(origin, direction),
          maxDistance: reach,
          where: (n) => !_isExcluded(n),
        );
        return hit == null
            ? null
            : CharacterRayHit(distance: hit.distance, normal: hit.worldNormal);
      }

      final hit = sweepVehicleHull(
        position: currentPos,
        displacement: moveDelta,
        oldHeading: previousHeading,
        newHeading: heading,
        halfWidth: bodyHalfWidth,
        halfLength: bodyHalfLength,
        probeHeight: collisionProbeHeight,
        cast: cast,
      );
      var fraction = hit?.fraction ?? 1.0;
      var collisionNormal = hit?.normal;
      if (moveDist > 1e-5) {
        final moveDir = moveDelta / moveDist;
        final movingForward =
            newForward.x * moveDir.x + newForward.y * moveDir.z >= 0;
        final bumperCenter =
            newForward * (movingForward ? bodyHalfLength : -bodyHalfLength);
        final extra = additionalObstacleSweep?.call(
          currentPos +
              vm.Vector3(bumperCenter.x, collisionProbeHeight, bumperCenter.y),
          moveDir,
          moveDist,
          bodyHalfWidth,
        );
        if (extra != null && extra / moveDist < fraction) {
          fraction = ((extra - .05) / moveDist).clamp(0.0, 1.0);
          collisionNormal = null;
        }
      }
      if (fraction < 1) {
        final normal = collisionNormal;
        final n = normal == null ? null : vm.Vector2(normal.x, normal.z);
        final into = n == null || n.length2 < .1
            ? speed
            : math.max(0.0, -velocityXZ.dot(n.normalized()));
        onCollision?.call(into);
        moveDelta *= fraction;
        heading = previousHeading + (heading - previousHeading) * fraction;
        if (n != null && n.length2 > .1) {
          n.normalize();
          final vn = velocityXZ.dot(n);
          if (vn < 0) velocityXZ -= n * vn;
          velocityXZ *= .78;
        } else {
          velocityXZ.setZero();
        }
        dynamics.stopYaw();
      }
    }

    // 5. Применяем смещение и поворот.
    final newPos = currentPos + moveDelta;
    final height = groundHeightAt;
    var groundY = groundPlaneHeight ?? newPos.y;
    if (height != null) {
      final contact = groundContact = WheelContact.sample(
        x: newPos.x,
        z: newPos.z,
        heading: heading,
        anchors: contactAnchors,
        heightAt: height,
      );
      groundY = contact.height;
      final blend = 1 - math.exp(-10 * dt);
      _terrainPitch += (contact.pitch - _terrainPitch) * blend;
      _terrainRoll += (contact.roll - _terrainRoll) * blend;
    } else {
      groundContact = null;
      _terrainPitch = _terrainRoll = 0;
    }
    final worldPos = vm.Vector3(newPos.x, groundY, newPos.z);
    final worldRot =
        vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), heading) *
        vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), _terrainPitch) *
        vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), _terrainRoll);
    final worldMat = vm.Matrix4.compose(worldPos, worldRot, node.scale);

    if (height != null && wheelNodes.isNotEmpty) {
      final upY = math.max(.5, worldMat.entry(1, 1));
      for (var i = 0; i < wheelNodes.length; i++) {
        final rest = _wheelRest[i];
        final center = worldMat.transform3(rest.clone());
        final shift = ((height(center.x, center.z) + rest.y - center.y) / upY)
            .clamp(-suspensionTravel, suspensionTravel);
        wheelNodes[i].position = rest + vm.Vector3(0, shift, 0);
      }
    }
    final parent = node.parent;
    if (parent != null) {
      final invParent = parent.globalTransform.clone()..invert();
      node.localTransform = invParent * worldMat;
    } else {
      node.localTransform = worldMat;
    }
  }
}
