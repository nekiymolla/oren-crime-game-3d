/// Уровень визуальных повреждений — переключение между preset-мешами
/// (см. vehicle.dart), не настоящая деформация кузова: та ждёт rigid-body
/// физики (см. заметку про flutter_scene_rapier в PROGRESS.md).
enum DamageLevel { pristine, damaged, wrecked }

/// Чистая (без Flutter/flutter_scene) логика накопления повреждений —
/// тестируется юнит-тестом без GPU. [VehicleControllerComponent] сообщает
/// скорость машины в момент остановки о препятствие (см. его `onCollision`)
/// через [registerCollision]; здесь это превращается в уровень повреждений.
class VehicleDamageState {
  VehicleDamageState({this.damagedThreshold = 12.0, this.wreckedThreshold = 30.0});

  /// Накопленный "урон" — грубо говоря, сумма скоростей всех ударов
  /// (м/с), не физически точная величина, просто монотонный счётчик.
  final double damagedThreshold;
  final double wreckedThreshold;

  double accumulatedImpact = 0.0;

  /// Ниже которой удар не считается — иначе любое мягкое касание бордюра
  /// или пешехода уже красило бы машину как повреждённую.
  static const double minImpactSpeed = 2.5;

  DamageLevel get level {
    if (accumulatedImpact >= wreckedThreshold) return DamageLevel.wrecked;
    if (accumulatedImpact >= damagedThreshold) return DamageLevel.damaged;
    return DamageLevel.pristine;
  }

  void registerCollision(double impactSpeed) {
    if (impactSpeed < minImpactSpeed) return;
    accumulatedImpact += impactSpeed;
  }
}
