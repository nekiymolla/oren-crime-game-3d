import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

/// Throttle/steer для одного тика AI-вождения — чистая функция (без
/// Flutter/flutter_scene), проверяется юнит-тестом без GPU (см.
/// PROGRESS.md, "Важный урок по тестированию"). Сам разгон/занос/
/// столкновения считает VehicleControllerComponent — эта функция только
/// решает, куда рулить и жать ли газ, теми же входами setInput ждёт от
/// джойстика игрока.
///
/// [heading] — курс машины в конвенции VehicleControllerComponent.heading
/// (0 = +Z, положительное вращение — как у yaw в игре). [position]/
/// [targetPosition] — только X/Z считаются (высота дороги везде ~0).
({double throttle, double steer}) computePoliceInput({
  required vm.Vector3 position,
  required double heading,
  required vm.Vector3 targetPosition,
}) {
  final dx = targetPosition.x - position.x;
  final dz = targetPosition.z - position.z;
  final distance = math.sqrt(dx * dx + dz * dz);
  if (distance < 0.2) return (throttle: 0.0, steer: 0.0);

  final desiredHeading = math.atan2(dx, dz);
  var diff = desiredHeading - heading;
  diff = (diff + math.pi) % (2 * math.pi) - math.pi;

  final steer = (diff / (math.pi / 2)).clamp(-1.0, 1.0);
  // Сбрасываем газ в крутых поворотах — иначе AI-машина на полной скорости
  // срезает угол и утыкается в здание вместо доворота (см.
  // VehicleControllerComponent — сцепление падает с ростом скорости, резкий
  // руль на скорости даёт занос, а не чистый разворот).
  final throttle = diff.abs() > math.pi * 0.4 ? 0.5 : 1.0;

  return (throttle: throttle, steer: steer);
}

/// Газ перед поворотом маршрута: на подходе к путевой точке, после
/// которой дорога круто поворачивает, машина сбрасывает скорость до
/// [cornerSpeed] — иначе на 13+ м/с она вылетает в угол дома и
/// застревает (замечено на живой погоне). [turnAngle] — угол между
/// подходом к точке и следующим отрезком, рад.
double cornerThrottle({
  required double baseThrottle,
  required double speed,
  required double distanceToWaypoint,
  required double turnAngle,
  double brakeZone = 18.0,
  double cornerSpeed = 7.0,
}) {
  if (turnAngle < math.pi / 4 || distanceToWaypoint > brakeZone) return baseThrottle;
  // Чем круче поворот, тем медленнее его проходить.
  final allowed = cornerSpeed * (1.0 - 0.4 * ((turnAngle - math.pi / 4) / (math.pi * 3 / 4)).clamp(0.0, 1.0));
  if (speed > allowed + 1.0) return -1.0;
  if (speed > allowed) return 0.0;
  return baseThrottle;
}

/// Выбирание из тупика: машина жмёт газ, но стоит — значит упёрлась.
/// Хранится в машине AI, шаг [update] решает, сдавать ли назад сейчас.
class StuckRecovery {
  /// Сколько стоять "упёршись", прежде чем сдавать назад, и как долго.
  static const double stuckAfterSeconds = 1.2;
  static const double reverseSeconds = 1.3;

  double _stuckSeconds = 0.0;
  double _reverseLeft = 0.0;

  bool get isReversing => _reverseLeft > 0.0;

  /// [speed] — текущая скорость, [wantsToMove] — AI хочет ехать (газ > 0).
  /// Возвращает true, если в этот кадр надо ехать назад.
  bool update(double dt, {required double speed, required bool wantsToMove}) {
    if (_reverseLeft > 0.0) {
      _reverseLeft -= dt;
      return _reverseLeft > 0.0;
    }
    if (wantsToMove && speed < 0.8) {
      _stuckSeconds += dt;
      if (_stuckSeconds >= stuckAfterSeconds) {
        _stuckSeconds = 0.0;
        _reverseLeft = reverseSeconds;
        return true;
      }
    } else {
      _stuckSeconds = 0.0;
    }
    return false;
  }
}

/// Есть ли машина прямо по курсу ближе [lookAhead] метров (в коридоре
/// шириной ±[halfWidth]) — тогда полиция объезжает её по встречке, а не
/// стоит в пробке с мигалками.
bool isBlockedAhead(
  vm.Vector3 position,
  double heading,
  Iterable<vm.Vector3> blockers, {
  double lookAhead = 12.0,
  double halfWidth = 1.6,
}) {
  final forwardX = math.sin(heading);
  final forwardZ = math.cos(heading);
  for (final other in blockers) {
    final dx = other.x - position.x;
    final dz = other.z - position.z;
    final along = dx * forwardX + dz * forwardZ;
    if (along <= 1.0 || along > lookAhead) continue;
    final side = dx * forwardZ - dz * forwardX;
    if (side.abs() <= halfWidth) return true;
  }
  return false;
}

/// Точка объезда: [target], сдвинутая на [offset] метров влево от
/// направления движения (левее — встречная полоса).
vm.Vector3 overtakeTarget(vm.Vector3 position, vm.Vector3 target, {double offset = 3.5}) {
  final dx = target.x - position.x;
  final dz = target.z - position.z;
  final length = math.sqrt(dx * dx + dz * dz);
  if (length < 1e-3) return target.clone();
  // Влево от курса — (dz, -dx): зеркало rightOf из traffic_car.dart.
  // Трафик держится правее оси дороги, так что слева — встречка.
  return vm.Vector3(target.x + dz / length * offset, target.y, target.z - dx / length * offset);
}
