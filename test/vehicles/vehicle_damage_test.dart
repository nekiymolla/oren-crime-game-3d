import 'package:crime_oren/vehicles/vehicle_damage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('слабые касания ниже minImpactSpeed не считаются', () {
    final damage = VehicleDamageState();
    damage.registerCollision(1.0);
    expect(damage.accumulatedImpact, 0.0);
    expect(damage.level, DamageLevel.pristine);
  });

  test('накопленные удары поднимают уровень до damaged, потом wrecked', () {
    final damage = VehicleDamageState(damagedThreshold: 10.0, wreckedThreshold: 25.0);

    damage.registerCollision(6.0);
    expect(damage.level, DamageLevel.pristine);

    damage.registerCollision(6.0); // итого 12 >= 10
    expect(damage.level, DamageLevel.damaged);

    damage.registerCollision(20.0); // итого 32 >= 25
    expect(damage.level, DamageLevel.wrecked);
  });
}
