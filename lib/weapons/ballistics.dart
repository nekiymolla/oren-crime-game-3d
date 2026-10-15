import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import 'weapon_config.dart';

/// Куда попала пуля — от этого зависит урон (ТЗ, раздел 13: разные зоны
/// тела).
enum BodyZone { head, torso, legs }

/// Зона по высоте попадания над ступнями ([heightAboveFeet]) при росте
/// [bodyHeight]: верхние ~18% — голова, нижние ~45% — ноги.
BodyZone zoneForHitHeight(double heightAboveFeet, double bodyHeight) {
  final relative = heightAboveFeet / bodyHeight;
  if (relative >= 0.82) return BodyZone.head;
  if (relative < 0.45) return BodyZone.legs;
  return BodyZone.torso;
}

double damageFor(WeaponConfig weapon, BodyZone zone) => switch (zone) {
  BodyZone.head => weapon.damage * weapon.headshotMultiplier,
  BodyZone.torso => weapon.damage,
  BodyZone.legs => weapon.damage * weapon.legMultiplier,
};

/// Пересечение луча с вертикальной капсулой (стоящий человек): ступни в
/// [feet], полный рост [height], радиус [radius]. [direction] — единичный.
/// Возвращает расстояние вдоль луча до первого касания или null.
/// Аналитически, без геометрии сцены: пешеходы — инстансы одного меша, и
/// raycastNode их по отдельности не видит.
double? rayVerticalCapsule(
  vm.Vector3 origin,
  vm.Vector3 direction,
  double maxDistance,
  vm.Vector3 feet,
  double radius,
  double height,
) {
  // Ось капсулы — отрезок a..b, сферы радиуса [radius] на концах.
  final a = vm.Vector3(feet.x, feet.y + radius, feet.z);
  final segment = math.max(0.0, height - 2 * radius);
  final ba = vm.Vector3(0, segment, 0);
  final oa = origin - a;

  final baba = ba.dot(ba);
  final bard = ba.dot(direction);
  final baoa = ba.dot(oa);
  final rdoa = direction.dot(oa);
  final oaoa = oa.dot(oa);

  double? best;
  if (baba > 1e-9) {
    // Боковая (цилиндрическая) часть.
    final qa = baba - bard * bard;
    final qb = baba * rdoa - baoa * bard;
    final qc = baba * oaoa - baoa * baoa - radius * radius * baba;
    final h = qb * qb - qa * qc;
    if (h >= 0.0 && qa > 1e-9) {
      final t = (-qb - math.sqrt(h)) / qa;
      final y = baoa + t * bard;
      if (y > 0.0 && y < baba && t >= 0.0) best = t;
    }
  }
  if (best == null) {
    // Полусферы на концах.
    for (final center in [a, a + ba]) {
      final t = _raySphere(origin, direction, center, radius);
      if (t != null && (best == null || t < best)) best = t;
    }
  }
  if (best == null || best > maxDistance) return null;
  return best;
}

double? _raySphere(vm.Vector3 origin, vm.Vector3 direction, vm.Vector3 center, double radius) {
  final oc = origin - center;
  final b = oc.dot(direction);
  final c = oc.dot(oc) - radius * radius;
  final h = b * b - c;
  if (h < 0.0) return null;
  final t = -b - math.sqrt(h);
  if (t >= 0.0) return t;
  // Начало луча внутри сферы — попадание сразу.
  return c <= 0.0 ? 0.0 : null;
}

/// Случайное направление в конусе с полууглом [halfAngleRadians] вокруг
/// [direction] (единичного), равномерно по телесному углу.
vm.Vector3 spreadDirection(vm.Vector3 direction, double halfAngleRadians, math.Random random) {
  if (halfAngleRadians <= 0.0) return direction.normalized();
  final cosMax = math.cos(halfAngleRadians);
  final cosTheta = 1.0 - random.nextDouble() * (1.0 - cosMax);
  final sinTheta = math.sqrt(math.max(0.0, 1.0 - cosTheta * cosTheta));
  final phi = random.nextDouble() * 2 * math.pi;

  final w = direction.normalized();
  final helper = w.y.abs() < 0.99 ? vm.Vector3(0, 1, 0) : vm.Vector3(1, 0, 0);
  final u = helper.cross(w)..normalize();
  final v = w.cross(u);
  return (u * (math.cos(phi) * sinTheta) + v * (math.sin(phi) * sinTheta) + w * cosTheta)..normalize();
}

/// Мягкий автоприцел: из [aimPoints] (точки на телах целей) выбирает ту,
/// что ближе всего к линии прицела по углу, — если она в пределах
/// [maxAngleRadians] и [maxDistance] от [origin]. Возвращает индекс или
/// null.
int? pickAimAssistTarget(
  vm.Vector3 origin,
  vm.Vector3 aimDirection,
  List<vm.Vector3> aimPoints, {
  required double maxAngleRadians,
  required double maxDistance,
}) {
  final cosLimit = math.cos(maxAngleRadians);
  final forward = aimDirection.normalized();
  int? best;
  var bestCos = cosLimit;
  for (var i = 0; i < aimPoints.length; i++) {
    final to = aimPoints[i] - origin;
    final distance = to.length;
    if (distance < 1e-3 || distance > maxDistance) continue;
    final cos = to.dot(forward) / distance;
    if (cos >= bestCos) {
      bestCos = cos;
      best = i;
    }
  }
  return best;
}
