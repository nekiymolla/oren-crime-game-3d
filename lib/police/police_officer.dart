import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

/// Полицейский пешком — вышел из патрульной машины при серьёзном розыске
/// (см. PoliceOfficers). Чистое состояние и шаг логики, проверены тестами;
/// рендер и лучи — снаружи.
class PoliceOfficer {
  PoliceOfficer({required this.position, required this.unitId, this.yaw = 0.0});

  vm.Vector3 position;
  double yaw;

  /// Из какой машины (PoliceSystem) — по нему офицеров отзывают обратно.
  final int unitId;

  static const double maxHealth = 100.0;
  double health = maxHealth;
  bool isDead = false;
  double deadSeconds = 0.0;

  /// Не стреляет сразу после выхода из машины и между выстрелами.
  double fireCooldown = 0.8;

  /// Сколько секунд подряд не видит игрока — по нему машина решает, что
  /// игрок ушёл, и забирает офицеров обратно.
  double secondsWithoutSight = 0.0;

  bool get isShootable => !isDead;

  /// true — убит этим попаданием.
  bool takeDamage(double damage, vm.Vector3 from) {
    if (isDead) return false;
    health -= damage;
    if (health > 0.0) return false;
    health = 0.0;
    isDead = true;
    final away = vm.Vector3(position.x - from.x, 0, position.z - from.z);
    if (away.length2 > 1e-6) yaw = math.atan2(away.x, away.z);
    return true;
  }
}

/// Числа поведения офицеров.
abstract final class OfficerTuning {
  /// Скорость сближения (бегом), м/с.
  static const double runSpeed = 3.8;

  /// Ближе этого не подходят — стоят и стреляют.
  static const double stopDistance = 9.0;

  /// Дальше этого не стреляют.
  static const double fireRange = 40.0;

  /// Секунд между выстрелами (с разбросом ±30%).
  static const double fireInterval = 1.1;

  /// Урон попадания по игроку пешком (в машине — вдвое меньше).
  static const double damage = 7.0;
}

/// Свободен ли путь на [distance] метров из [from] в горизонтальном
/// направлении [direction] (единичном) — луч на уровне корпуса.
typedef OfficerPathProbe = bool Function(vm.Vector3 from, vm.Vector3 direction, double distance);

/// Один кадр офицера: поворачивается к игроку, при прямой видимости
/// сближается до [OfficerTuning.stopDistance] и стреляет, когда готов.
/// Без видимости обходит то, что закрывает игрока (машину, угол дома):
/// идёт в его сторону, щупая путь коротким лучом [pathClear] — прямо,
/// затем ±45° и ±90°. Сквозь стены так не пройти: луч их видит.
/// Возвращает true, если в этом кадре выстрел.
bool stepOfficer(
  PoliceOfficer officer,
  vm.Vector3 target,
  double dt, {
  required bool hasLineOfSight,
  required math.Random random,
  OfficerPathProbe? pathClear,
}) {
  if (officer.isDead) {
    officer.deadSeconds += dt;
    return false;
  }
  officer.fireCooldown = math.max(0.0, officer.fireCooldown - dt);

  final to = vm.Vector3(target.x - officer.position.x, 0, target.z - officer.position.z);
  final distance = to.length;
  if (distance > 1e-3) officer.yaw = math.atan2(to.x, to.z);

  if (!hasLineOfSight) {
    officer.secondsWithoutSight += dt;
    if (pathClear != null && distance > OfficerTuning.stopDistance * 0.5) {
      final toward = math.atan2(to.x, to.z);
      for (final turn in const [0.0, math.pi / 4, -math.pi / 4, math.pi / 2, -math.pi / 2]) {
        final angle = toward + turn;
        final direction = vm.Vector3(math.sin(angle), 0, math.cos(angle));
        if (!pathClear(officer.position, direction, _probeDistance)) continue;
        officer.position += direction * (OfficerTuning.runSpeed * 0.8 * dt);
        officer.yaw = angle;
        break;
      }
    }
    return false;
  }
  officer.secondsWithoutSight = 0.0;

  if (distance > OfficerTuning.stopDistance) {
    final step = math.min(OfficerTuning.runSpeed * dt, distance - OfficerTuning.stopDistance);
    officer.position += to / distance * step;
  }

  if (officer.fireCooldown > 0.0 || distance > OfficerTuning.fireRange) return false;
  officer.fireCooldown = OfficerTuning.fireInterval * (0.7 + random.nextDouble() * 0.6);
  return true;
}

/// Насколько далеко вперёд щупать путь при обходе.
const double _probeDistance = 1.5;

/// Шанс, что выстрел офицера попадёт: падает с дистанцией, бегущего и
/// едущего зацепить труднее.
double officerHitChance(double distance, {required double targetSpeed, required bool targetInVehicle}) {
  // 0.55 вплотную -> 0.12 на 40 м.
  final t = (distance / OfficerTuning.fireRange).clamp(0.0, 1.0);
  var chance = 0.55 + (0.12 - 0.55) * t;
  if (targetSpeed > 6.0) {
    chance *= 0.4;
  } else if (targetSpeed > 3.0) {
    chance *= 0.65;
  }
  if (targetInVehicle) chance *= 0.8;
  return chance;
}
