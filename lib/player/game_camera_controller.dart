import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Камера от третьего лица, как встроенный [FollowCameraController], плюс
/// режим прицеливания: при [aiming] камера плавно подходит ближе и уходит
/// за правое плечо. Иначе прицел в центре экрана закрывал бы сам
/// персонаж — встроенная камера смотрит ровно в него.
///
/// Орбита (yaw/pitch/distance, orbitBy, жесты) — от базового класса;
/// переопределён только расчёт позиции в [update].
class GameCameraController extends FollowCameraController {
  GameCameraController({super.followTarget, super.distance, super.lookHeight, super.minPitch});

  /// Целимся (стрельба) — камера за плечом.
  bool aiming = false;

  /// Дистанция камеры в прицеливании (не дальше обычной).
  double aimDistance = 3.2;

  /// Насколько вправо от персонажа смещается точка взгляда в прицеливании.
  double shoulderOffset = 0.8;

  /// Скорость перехода в прицеливание и обратно, 1/с.
  static const double _aimBlendSpeed = 10.0;

  double _aimBlend = 0.0;
  final vm.Vector3 _position = vm.Vector3.zero();
  final vm.Vector3 _target = vm.Vector3.zero();
  bool _initialized = false;

  /// Где камера сейчас (со сглаживанием — то, что видно на экране).
  vm.Vector3 get eyePosition => _position;

  /// Точка в центре экрана — куда смотрит камера.
  vm.Vector3 get lookTarget => _target;

  /// Единичное направление взгляда — луч через центр экрана (прицел).
  vm.Vector3 get viewDirection => (_target - _position).normalized();

  @override
  void update(double deltaSeconds) {
    final dt = clampDeltaSeconds(deltaSeconds);
    final aimGoal = aiming ? 1.0 : 0.0;
    _aimBlend += (aimGoal - _aimBlend) * (1.0 - math.exp(-_aimBlendSpeed * dt));

    final base = followTarget?.globalTransform.getTranslation() ?? vm.Vector3.zero();
    final lookAt = base + vm.Vector3(0.0, lookHeight, 0.0) + right * (shoulderOffset * _aimBlend);
    final aimedDistance = math.min(distance, aimDistance);
    final effectiveDistance = distance + (aimedDistance - distance) * _aimBlend;
    final horizontal = math.cos(pitch) * effectiveDistance;
    final desired =
        lookAt +
        vm.Vector3(-math.sin(yaw), 0.0, -math.cos(yaw)) * horizontal +
        vm.Vector3(0.0, math.sin(pitch) * effectiveDistance, 0.0);

    if (!_initialized) {
      _position.setFrom(desired);
      _target.setFrom(lookAt);
      _initialized = true;
    } else {
      final r = smoothingResponse(dt);
      _position.addScaled(desired - _position, r);
      _target.addScaled(lookAt - _target, r);
    }
    node.lookAtFrom(_position, _target);
  }
}
