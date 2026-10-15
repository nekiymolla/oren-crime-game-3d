import 'dart:convert';
import 'dart:io';

import 'package:crime_oren/weapons/weapon_config.dart';
import 'package:crime_oren/weapons/weapon_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _pistol = WeaponConfig(
  id: 'test_pistol',
  displayName: 'тест',
  damage: 34,
  rangeMeters: 50,
  fireRate: 4,
  magazineSize: 3,
  startingReserveAmmo: 4,
  reloadSeconds: 1.0,
  spreadDegrees: 1.0,
  recoilDegrees: 1.0,
  recoilRecoveryDegreesPerSecond: 2.0,
  maxRecoilDegrees: 2.5,
);

void main() {
  test('weapons.json читается, оружие по умолчанию есть', () {
    final json = jsonDecode(File('assets/data/weapons.json').readAsStringSync()) as Map<String, dynamic>;
    final catalog = WeaponCatalog.fromJson(json);
    final pistol = catalog.defaultWeapon;
    expect(pistol.id, catalog.defaultWeaponId);
    expect(pistol.magazineSize, greaterThan(0));
    // Пистолет: три в корпус, один в голову (здоровье пешехода — 100).
    expect(pistol.damage * 3, greaterThanOrEqualTo(100));
    expect(pistol.damage * 2, lessThan(100));
    expect(pistol.damage * pistol.headshotMultiplier, greaterThanOrEqualTo(100));
  });

  test('темп стрельбы: при зажатой кнопке не чаще fireRate', () {
    final weapon = WeaponState(_pistol);
    var shots = 0;
    // Полсекунды по кадрам 60 Гц — при 4 выстр/с это 2 выстрела.
    for (var i = 0; i < 30; i++) {
      if (weapon.tryFire()) shots++;
      weapon.update(1 / 60);
    }
    expect(shots, 2);
  });

  test('пустой магазин сам перезаряжается из запаса, запас кончается', () {
    final weapon = WeaponState(_pistol);
    for (var i = 0; i < 3; i++) {
      expect(weapon.tryFire(), isTrue);
      weapon.update(0.3);
    }
    expect(weapon.ammoInMagazine, 0);
    expect(weapon.isReloading, isTrue);
    expect(weapon.tryFire(), isFalse);

    weapon.update(1.1);
    expect(weapon.isReloading, isFalse);
    expect(weapon.ammoInMagazine, 3);
    expect(weapon.reserveAmmo, 1);

    // Второй магазин — в запасе остался один патрон.
    for (var i = 0; i < 3; i++) {
      weapon.tryFire();
      weapon.update(0.3);
    }
    weapon.update(1.1);
    expect(weapon.ammoInMagazine, 1);
    expect(weapon.reserveAmmo, 0);
    expect(weapon.canReload, isFalse);
  });

  test('ручная перезарядка: не при полном магазине, доливает только недостающее', () {
    final weapon = WeaponState(_pistol);
    expect(weapon.startReload(), isFalse);
    weapon.tryFire();
    expect(weapon.startReload(), isTrue);
    weapon.update(1.1);
    expect(weapon.ammoInMagazine, 3);
    expect(weapon.reserveAmmo, 3);
  });

  test('отдача копится до предела и сходит со временем', () {
    final weapon = WeaponState(_pistol);
    expect(weapon.currentSpreadDegrees, 1.0);
    weapon.tryFire();
    expect(weapon.currentSpreadDegrees, closeTo(2.0, 1e-9));
    weapon.update(0.25);
    weapon.tryFire();
    weapon.update(0.25);
    weapon.tryFire();
    expect(weapon.currentSpreadDegrees, lessThanOrEqualTo(1.0 + 2.5 + 1e-9));
    weapon.update(5.0);
    expect(weapon.currentSpreadDegrees, 1.0);
  });
}
