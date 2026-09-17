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
