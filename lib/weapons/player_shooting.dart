import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import 'ballistics.dart';
import 'weapon_state.dart';

/// Луч пули против неподвижного мира (дома, машины): расстояние до
/// попадания или null.
typedef BulletRaycast = double? Function(vm.Vector3 origin, vm.Vector3 direction, double maxDistance);

/// В кого можно попасть — сейчас это пешеходы (PedestrianSystem). Интерфейс,
/// а не сам класс, чтобы логику стрельбы проверять тестами без GPU.
abstract interface class ShootTargets {
  ({int index, double distance, BodyZone zone})? raycastShootable(
    vm.Vector3 origin,
    vm.Vector3 direction,
    double maxDistance,
  );

  /// true — цель убита.
  bool applyShot(int index, double damage, vm.Vector3 from);

  void collectAimPoints(List<vm.Vector3> points, List<int> indices);

  /// Сколько живых услышали выстрел (и побежали).
  int scareAround(vm.Vector3 shooter, double radius);
}

/// Чем закончилась одна пуля — для эффектов (трассер, искры/кровь).
enum BulletImpact { none, world, flesh }

class BulletTrace {
  const BulletTrace(this.end, this.impact);

  final vm.Vector3 end;
  final BulletImpact impact;
}

/// Итог одного выстрела — для эффектов и розыска.
class ShotOutcome {
  ShotOutcome({required this.muzzle, required this.bullets, required this.wounded, required this.killed, required this.witnesses});

  final vm.Vector3 muzzle;
  final List<BulletTrace> bullets;
  final int wounded;
  final int killed;
  final int witnesses;
}

/// Стрельба игрока: куда летит пуля и в кого попадает. Прицел — луч из
/// камеры через центр экрана; пуля летит из ствола в точку, куда этот луч
/// упёрся (иначе из-за плеча камеры пуля шла бы параллельно прицелу и
/// мимо). Мягкий автоприцел подтягивает к ближайшей по углу цели.
class PlayerShooting {
  PlayerShooting({required this.weapon, required this.targets, required this.worldRaycast, math.Random? random})
    : _random = random ?? math.Random();

  final WeaponState weapon;
  final ShootTargets targets;
  final BulletRaycast worldRaycast;
  final math.Random _random;

  /// Насколько далеко слышен выстрел — пешеходы в этом радиусе бегут, а
  /// стрельба при них считается преступлением.
  static const double hearingRadius = 40.0;

  final List<vm.Vector3> _aimPoints = [];
  final List<int> _aimIndices = [];

  /// Кнопка огня зажата этот кадр: стреляет, если оружие готово. [eye] и
  /// [viewDirection] — камера (прицел в центре экрана), [muzzle] — ствол.
  ShotOutcome? tryFire({required vm.Vector3 eye, required vm.Vector3 viewDirection, required vm.Vector3 muzzle}) {
    if (!weapon.tryFire()) return null;
    final config = weapon.config;
    final aimPoint = _aimPoint(eye, viewDirection, muzzle);

    final toAim = aimPoint - muzzle;
    final center = toAim.length2 > 1e-6 ? toAim.normalized() : viewDirection.normalized();
    final spread = weapon.currentSpreadDegrees * math.pi / 180;

    final bullets = <BulletTrace>[];
    var wounded = 0;
    var killed = 0;
    for (var i = 0; i < config.pellets; i++) {
      final direction = spreadDirection(center, spread, _random);
      final worldT = worldRaycast(muzzle, direction, config.rangeMeters);
      final hit = targets.raycastShootable(muzzle, direction, worldT ?? config.rangeMeters);
      if (hit != null) {
        final died = targets.applyShot(hit.index, damageFor(config, hit.zone), muzzle);
        if (died) {
          killed++;
        } else {
          wounded++;
        }
        bullets.add(BulletTrace(muzzle + direction * hit.distance, BulletImpact.flesh));
      } else if (worldT != null) {
        bullets.add(BulletTrace(muzzle + direction * worldT, BulletImpact.world));
      } else {
        bullets.add(BulletTrace(muzzle + direction * config.rangeMeters, BulletImpact.none));
      }
    }

    final witnesses = targets.scareAround(muzzle, hearingRadius);
    return ShotOutcome(muzzle: muzzle, bullets: bullets, wounded: wounded, killed: killed, witnesses: witnesses);
  }

  /// Куда целимся: автоприцел, иначе первое, во что упирается луч
  /// камеры, иначе точка на дальности оружия.
  vm.Vector3 _aimPoint(vm.Vector3 eye, vm.Vector3 viewDirection, vm.Vector3 muzzle) {
    final config = weapon.config;
    final view = viewDirection.normalized();
    // Луч камеры начинается позади персонажа — дальность считаем от неё.
    final eyeToMuzzle = (muzzle - eye).dot(view);
    final reach = config.rangeMeters + math.max(0.0, eyeToMuzzle);

    if (config.aimAssistDegrees > 0.0) {
      _aimPoints.clear();
      _aimIndices.clear();
      targets.collectAimPoints(_aimPoints, _aimIndices);
      // Только цели перед стволом и в пределах дальности от него.
      for (var i = _aimPoints.length - 1; i >= 0; i--) {
        final fromMuzzle = _aimPoints[i] - muzzle;
        if (fromMuzzle.dot(view) <= 0.5 || fromMuzzle.length > config.rangeMeters) {
          _aimPoints.removeAt(i);
          _aimIndices.removeAt(i);
        }
      }
      final picked = pickAimAssistTarget(
        eye,
        view,
        _aimPoints,
        maxAngleRadians: config.aimAssistDegrees * math.pi / 180,
        maxDistance: reach,
      );
      if (picked != null) return _aimPoints[picked];
    }

    // Луч из камеры: начинаем от ствола по глубине, чтобы не упереться в
    // то, что между камерой и персонажем.
    final start = eye + view * math.max(0.0, eyeToMuzzle);
    final remaining = reach - math.max(0.0, eyeToMuzzle);
    final worldT = worldRaycast(start, view, remaining);
    final targetHit = targets.raycastShootable(start, view, worldT ?? remaining);
    final distance = targetHit?.distance ?? worldT ?? remaining;
    return start + view * distance;
  }
}

/// Несколько наборов целей как один (пешеходы и полицейские): индекс
/// цели кодирует, из какого она набора.
class CombinedShootTargets implements ShootTargets {
  CombinedShootTargets(this.parts);

  final List<ShootTargets> parts;

  static const int _stride = 1 << 16;

  final List<vm.Vector3> _points = [];
  final List<int> _indices = [];

  @override
  ({int index, double distance, BodyZone zone})? raycastShootable(vm.Vector3 origin, vm.Vector3 direction, double maxDistance) {
    ({int index, double distance, BodyZone zone})? best;
    for (var p = 0; p < parts.length; p++) {
      final hit = parts[p].raycastShootable(origin, direction, best?.distance ?? maxDistance);
      if (hit != null) best = (index: p * _stride + hit.index, distance: hit.distance, zone: hit.zone);
    }
    return best;
  }

  @override
  bool applyShot(int index, double damage, vm.Vector3 from) =>
      parts[index ~/ _stride].applyShot(index % _stride, damage, from);

  @override
  void collectAimPoints(List<vm.Vector3> points, List<int> indices) {
    for (var p = 0; p < parts.length; p++) {
      _points.clear();
      _indices.clear();
      parts[p].collectAimPoints(_points, _indices);
      points.addAll(_points);
      indices.addAll(_indices.map((i) => p * _stride + i));
    }
  }

  @override
  int scareAround(vm.Vector3 shooter, double radius) {
    var witnesses = 0;
    for (final part in parts) {
      witnesses += part.scareAround(shooter, radius);
    }
    return witnesses;
  }
}
