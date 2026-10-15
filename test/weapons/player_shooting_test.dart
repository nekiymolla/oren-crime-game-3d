import 'dart:math' as math;

import 'package:crime_oren/weapons/ballistics.dart';
import 'package:crime_oren/weapons/player_shooting.dart';
import 'package:crime_oren/weapons/weapon_config.dart';
import 'package:crime_oren/weapons/weapon_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Люди — стоящие капсулы, как у пешеходов.
class _FakeTargets implements ShootTargets {
  _FakeTargets(this.feet);

  final List<vm.Vector3> feet;
  final Map<int, double> damage = {};
  int scared = 0;

  @override
  ({int index, double distance, BodyZone zone})? raycastShootable(vm.Vector3 origin, vm.Vector3 direction, double maxDistance) {
    ({int index, double distance, BodyZone zone})? best;
    for (var i = 0; i < feet.length; i++) {
      final t = rayVerticalCapsule(origin, direction, best?.distance ?? maxDistance, feet[i], 0.3, 1.5);
      if (t == null) continue;
      best = (index: i, distance: t, zone: zoneForHitHeight(origin.y + direction.y * t - feet[i].y, 1.5));
    }
    return best;
  }

  @override
  bool applyShot(int index, double amount, vm.Vector3 from) {
    damage[index] = (damage[index] ?? 0) + amount;
    return damage[index]! >= 100;
  }

  @override
  void collectAimPoints(List<vm.Vector3> points, List<int> indices) {
    for (var i = 0; i < feet.length; i++) {
      points.add(feet[i] + vm.Vector3(0, 1.0, 0));
      indices.add(i);
    }
  }

  @override
  int scareAround(vm.Vector3 shooter, double radius) {
    scared++;
    return feet.where((f) => (f - shooter).length <= radius).length;
  }
}

const _pistol = WeaponConfig(
  id: 'p',
  displayName: 'p',
  damage: 34,
  headshotMultiplier: 3,
  rangeMeters: 50,
  fireRate: 100,
  magazineSize: 50,
  reloadSeconds: 1,
  spreadDegrees: 0,
  aimAssistDegrees: 7,
);

void main() {
  // Камера позади и чуть выше игрока, ствол у плеча, смотрим вдоль +Z.
  final eye = vm.Vector3(0.8, 2.0, -3.0);
  final view = vm.Vector3(0, -0.02, 1).normalized();
  final muzzle = vm.Vector3(0.3, 1.35, 0.5);

  test('прицел чуть мимо — автоприцел попадает, три выстрела убивают', () {
    final targets = _FakeTargets([vm.Vector3(2.0, 0, 20)]);
    final shooting = PlayerShooting(weapon: WeaponState(_pistol), targets: targets, worldRaycast: (_, _, _) => null);
    final first = shooting.tryFire(eye: eye, viewDirection: view, muzzle: muzzle)!;
    expect(first.wounded, 1);
    expect(first.bullets.single.impact, BulletImpact.flesh);
    expect(first.witnesses, 1);
    ShotOutcome? last;
    for (var i = 0; i < 2; i++) {
      shooting.weapon.update(0.1);
      last = shooting.tryFire(eye: eye, viewDirection: view, muzzle: muzzle);
    }
    expect(last!.killed, 1);
  });

  test('стена между стволом и целью — пуля в стену', () {
    final targets = _FakeTargets([vm.Vector3(0.3, 0, 20)]);
    final shooting = PlayerShooting(
      weapon: WeaponState(_pistol),
      targets: targets,
      worldRaycast: (origin, direction, max) => origin.z < 10 ? math.min(max, (10 - origin.z) / direction.z) : null,
    );
    final shot = shooting.tryFire(eye: eye, viewDirection: view, muzzle: muzzle)!;
    expect(shot.bullets.single.impact, BulletImpact.world);
    expect(shot.bullets.single.end.z, closeTo(10, 1e-6));
    expect(targets.damage, isEmpty);
  });

  test('цель далеко в стороне — промах в пустоту на дальности оружия', () {
    final targets = _FakeTargets([vm.Vector3(15, 0, 20)]);
    final shooting = PlayerShooting(weapon: WeaponState(_pistol), targets: targets, worldRaycast: (_, _, _) => null);
    final shot = shooting.tryFire(eye: eye, viewDirection: view, muzzle: muzzle)!;
    expect(shot.bullets.single.impact, BulletImpact.none);
    expect((shot.bullets.single.end - muzzle).length, closeTo(50, 1e-4));
    expect(targets.damage, isEmpty);
  });

  test('цель позади ствола автоприцел не берёт', () {
    final targets = _FakeTargets([vm.Vector3(0.5, 0, -1.5)]);
    final shooting = PlayerShooting(weapon: WeaponState(_pistol), targets: targets, worldRaycast: (_, _, _) => null);
    final shot = shooting.tryFire(eye: eye, viewDirection: view, muzzle: muzzle)!;
    expect(targets.damage, isEmpty);
    expect(shot.bullets.single.end.z, greaterThan(muzzle.z));
  });

  test('без патронов не стреляет', () {
    final weapon = WeaponState(_pistol)..ammoInMagazine = 0;
    final shooting = PlayerShooting(weapon: weapon, targets: _FakeTargets([]), worldRaycast: (_, _, _) => null);
    expect(shooting.tryFire(eye: eye, viewDirection: view, muzzle: muzzle), isNull);
  });
}
