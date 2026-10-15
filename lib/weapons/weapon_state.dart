import 'dart:math' as math;

import 'weapon_config.dart';

/// Что у оружия в руках прямо сейчас: патроны, перезарядка, остывание
/// между выстрелами, накопленная отдача. Чистая логика без сцены —
/// проверена тестами; стреляет ли пуля куда-то, решает PlayerShooting.
class WeaponState {
  WeaponState(this.config)
    : ammoInMagazine = config.magazineSize,
      reserveAmmo = config.startingReserveAmmo;

  final WeaponConfig config;

  int ammoInMagazine;
  int reserveAmmo;

  double _cooldown = 0.0;
  double _reloadLeft = 0.0;
  double _recoilDegrees = 0.0;

  bool get isReloading => _reloadLeft > 0.0;

  /// 0..1 — для индикатора перезарядки в HUD.
  double get reloadProgress => isReloading ? 1.0 - _reloadLeft / config.reloadSeconds : 0.0;

  /// Полуугол разброса сейчас: базовый плюс накопленная отдача.
  double get currentSpreadDegrees => config.spreadDegrees + _recoilDegrees;

  bool get canReload => !isReloading && ammoInMagazine < config.magazineSize && reserveAmmo > 0;

  void update(double dt) {
    _cooldown = math.max(0.0, _cooldown - dt);
    _recoilDegrees = math.max(0.0, _recoilDegrees - config.recoilRecoveryDegreesPerSecond * dt);
    if (isReloading) {
      _reloadLeft -= dt;
      if (_reloadLeft <= 0.0) {
        _reloadLeft = 0.0;
        final loaded = math.min(config.magazineSize - ammoInMagazine, reserveAmmo);
        ammoInMagazine += loaded;
        reserveAmmo -= loaded;
      }
    }
  }

  /// Начать перезарядку, если есть смысл. false — нечего или уже идёт.
  bool startReload() {
    if (!canReload) return false;
    _reloadLeft = config.reloadSeconds;
    return true;
  }

  /// Попытка выстрела (кнопка зажата). true — выстрел произошёл: патрон
  /// списан, отдача добавлена. Пустой магазин сам уходит в перезарядку.
  bool tryFire() {
    if (isReloading || _cooldown > 0.0) return false;
    if (ammoInMagazine <= 0) {
      startReload();
      return false;
    }
    ammoInMagazine--;
    _cooldown = config.secondsBetweenShots;
    _recoilDegrees = math.min(config.maxRecoilDegrees, _recoilDegrees + config.recoilDegrees);
    if (ammoInMagazine == 0) startReload();
    return true;
  }
}
