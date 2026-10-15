import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Числа одного оружия из assets/data/weapons.json (ТЗ, раздел 12: оружие
/// data-driven). Пистолет, дробовик и автомат различаются только числами:
/// дробовик — [pellets] > 1 и широкий [spreadDegrees], автомат — высокий
/// [fireRate].
class WeaponConfig {
  const WeaponConfig({
    required this.id,
    required this.displayName,
    required this.damage,
    this.headshotMultiplier = 2.0,
    this.legMultiplier = 0.6,
    required this.rangeMeters,
    required this.fireRate,
    required this.magazineSize,
    this.startingReserveAmmo = 0,
    required this.reloadSeconds,
    required this.spreadDegrees,
    this.recoilDegrees = 0.0,
    this.recoilRecoveryDegreesPerSecond = 6.0,
    this.maxRecoilDegrees = 4.0,
    this.aimAssistDegrees = 0.0,
    this.pellets = 1,
  });

  factory WeaponConfig.fromJson(Map<String, dynamic> json) {
    double number(String key, double fallback) => (json[key] as num?)?.toDouble() ?? fallback;
    return WeaponConfig(
      id: json['id'] as String,
      displayName: json['displayName'] as String? ?? json['id'] as String,
      damage: (json['damage'] as num).toDouble(),
      headshotMultiplier: number('headshotMultiplier', 2.0),
      legMultiplier: number('legMultiplier', 0.6),
      rangeMeters: (json['rangeMeters'] as num).toDouble(),
      fireRate: (json['fireRate'] as num).toDouble(),
      magazineSize: json['magazineSize'] as int,
      startingReserveAmmo: json['startingReserveAmmo'] as int? ?? 0,
      reloadSeconds: (json['reloadSeconds'] as num).toDouble(),
      spreadDegrees: (json['spreadDegrees'] as num).toDouble(),
      recoilDegrees: number('recoilDegrees', 0.0),
      recoilRecoveryDegreesPerSecond: number('recoilRecoveryDegreesPerSecond', 6.0),
      maxRecoilDegrees: number('maxRecoilDegrees', 4.0),
      aimAssistDegrees: number('aimAssistDegrees', 0.0),
      pellets: json['pellets'] as int? ?? 1,
    );
  }

  final String id;
  final String displayName;

  /// Урон одной пули (дробины) в корпус. Здоровье пешехода — 100.
  final double damage;
  final double headshotMultiplier;
  final double legMultiplier;

  /// Дальше пуля не летит (и автоприцел дальше не ищет цели).
  final double rangeMeters;

  /// Выстрелов в секунду при зажатой кнопке.
  final double fireRate;
  final int magazineSize;

  /// Патронов в запасе (кроме магазина) на старте.
  final int startingReserveAmmo;
  final double reloadSeconds;

  /// Полуугол конуса разброса, градусы — у неподвижного стрелка.
  final double spreadDegrees;

  /// Отдача: на сколько градусов растёт разброс с каждым выстрелом, как
  /// быстро она сходит и до какого предела копится при частой стрельбе.
  final double recoilDegrees;
  final double recoilRecoveryDegreesPerSecond;
  final double maxRecoilDegrees;

  /// Мягкий автоприцел: цель в пределах этого угла от прицела берётся
  /// автоматически. На тач-экране без него стрелять почти невозможно —
  /// одна рука на джойстике, другая на кнопке огня.
  final double aimAssistDegrees;

  /// Пуль за выстрел — больше одной у дробовика.
  final int pellets;

  double get secondsBetweenShots => 1.0 / fireRate;
}

/// Весь набор оружия и то, с чем игрок начинает.
class WeaponCatalog {
  const WeaponCatalog({required this.weapons, required this.defaultWeaponId});

  factory WeaponCatalog.fromJson(Map<String, dynamic> json) => WeaponCatalog(
    weapons: [
      for (final entry in json['weapons'] as List) WeaponConfig.fromJson(entry as Map<String, dynamic>),
    ],
    defaultWeaponId: json['defaultWeapon'] as String,
  );

  final List<WeaponConfig> weapons;
  final String defaultWeaponId;

  WeaponConfig get defaultWeapon => weapons.firstWhere((w) => w.id == defaultWeaponId, orElse: () => weapons.first);
}

Future<WeaponCatalog> loadWeaponCatalog() async {
  final raw = await rootBundle.loadString('assets/data/weapons.json');
  return WeaponCatalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
