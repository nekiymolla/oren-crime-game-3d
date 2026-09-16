import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Kinematic-модель вождения "в духе" GTA — не настоящая rigid-body физика
/// (подвески/столкновений нет), но с нелинейным разгоном, зависящим от
/// скорости рулением и заносом на резких поворотах на скорости, чтобы
/// управление ощущалось увесисто, а не как игрушечная тележка.
///
/// Настоящая физика столкновений/подвески — апгрейд на flutter_scene_rapier
/// после того, как этот пакет выйдет из experimental-статуса (см. README
/// пакета: сейчас там нет готового компонента "машина", только rigid body +
/// joints, из которых её пришлось бы собирать с нуля).
class VehicleControllerComponent extends Component {
  VehicleControllerComponent({
    required this.maxSpeed,
    required this.acceleration,
    required this.braking,
    double? reverseMaxSpeed,
    this.drag = 3.0,
    this.maxSteerAngle = 0.55,
    this.wheelBase = 2.6,
    this.groundPlaneHeight = 0.0,
    this.gripAtLowSpeed = 14.0,
    this.gripAtHighSpeed = 4.0,
    this.driftThresholdSpeed = 9.0,
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

  /// Максимальный угол поворота колёс, рад.
  double maxSteerAngle;

  /// Колёсная база — влияет на радиус разворота (велосипедная модель).
  double wheelBase;

  /// Заглушка вместо raycast до земли, пока нет rigid-body физики.
  double? groundPlaneHeight;

  /// Насколько быстро продольная скорость "прилипает" к направлению носа
  /// машины на низкой/высокой скорости — ниже значение на высокой скорости
  /// даёт занос в резких поворотах вместо мгновенного разворота вектора.
  double gripAtLowSpeed;
  double gripAtHighSpeed;

  /// Скорость, начиная с которой сцепление начинает падать к gripAtHighSpeed.
  double driftThresholdSpeed;

  /// Скорость машины как вектор в мировых XZ (не всегда совпадает с
  /// направлением носа — расхождение и есть занос).
  vm.Vector2 velocityXZ = vm.Vector2.zero();

  double _yaw = 0.0;
  double _throttleInput = 0.0;
  double _steerInput = 0.0;

  double get speed => velocityXZ.length;

  /// Насколько текущее движение "не туда, куда смотрит машина" — 0 = едет
  /// строго носом вперёд, ближе к 1 = боком (для UI/звука заноса позже).
  double get driftFactor {
    if (speed < 0.5) return 0.0;
    final forward = vm.Vector2(math.sin(_yaw), math.cos(_yaw));
    final align = (velocityXZ.normalized()).dot(forward).clamp(-1.0, 1.0);
    return (1.0 - align).clamp(0.0, 1.0);
  }

  void setInput({required double throttle, required double steer}) {
    _throttleInput = throttle.clamp(-1.0, 1.0);
    _steerInput = steer.clamp(-1.0, 1.0);
  }

  @override
  void update(double deltaSeconds) => fixedUpdate(deltaSeconds);

  @override
  void fixedUpdate(double fixedDt) {
    final dt = fixedDt;
    if (dt <= 0.0 || !isAttached) return;

    final forward = vm.Vector2(math.sin(_yaw), math.cos(_yaw));
    var forwardSpeed = velocityXZ.dot(forward);

    // 1. Продольная динамика вдоль носа машины.
    if (_throttleInput.abs() > 0.02) {
      if (_throttleInput > 0) {
        forwardSpeed += acceleration * _throttleInput * dt;
      } else {
        // Тормоз, если едем вперёд; иначе — разгон назад.
        if (forwardSpeed > 0.05) {
          forwardSpeed = math.max(0, forwardSpeed + braking * _throttleInput * dt);
        } else {
          forwardSpeed += acceleration * 0.6 * _throttleInput * dt;
        }
      }
      forwardSpeed = forwardSpeed.clamp(-reverseMaxSpeed, maxSpeed);
    } else {
      final decel = drag * dt;
      if (forwardSpeed > 0) {
        forwardSpeed = math.max(0, forwardSpeed - decel);
      } else if (forwardSpeed < 0) {
        forwardSpeed = math.min(0, forwardSpeed + decel);
      }
    }

    // 2. Руление — велосипедная модель; радиус разворота зависит от скорости.
    if (forwardSpeed.abs() > 0.05) {
      final turnRate = (forwardSpeed / wheelBase) * math.tan(_steerInput * maxSteerAngle);
      _yaw += turnRate * dt;
    }

    // 3. Занос: на низкой скорости сцепление почти полное (вектор скорости
    // мгновенно доворачивается за носом), на высокой — падает, и вектор
    // скорости "отстаёт" от разворота носа, машину сносит боком.
    final newForward = vm.Vector2(math.sin(_yaw), math.cos(_yaw));
    final targetVelocity = newForward * forwardSpeed;
    final speedFactor = (speed / driftThresholdSpeed).clamp(0.0, 1.0);
    final grip = gripAtLowSpeed + (gripAtHighSpeed - gripAtLowSpeed) * speedFactor;
    final gripT = 1.0 - math.exp(-grip * dt);
    velocityXZ += (targetVelocity - velocityXZ) * gripT;

    // 4. Применяем смещение и поворот.
    final currentPos = (node.globalTransform * vm.Vector4(0, 0, 0, 1)).xyz;
    final newPos = currentPos + vm.Vector3(velocityXZ.x, 0, velocityXZ.y) * dt;
    final groundY = groundPlaneHeight ?? newPos.y;
    final worldPos = vm.Vector3(newPos.x, groundY, newPos.z);
    final worldRot = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _yaw);
    final worldMat = vm.Matrix4.compose(worldPos, worldRot, node.scale);

    final parent = node.parent;
    if (parent != null) {
      final invParent = parent.globalTransform.clone()..invert();
      node.localTransform = invParent * worldMat;
    } else {
      node.localTransform = worldMat;
    }
  }
}
