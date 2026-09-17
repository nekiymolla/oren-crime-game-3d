import 'package:crime_oren/vehicles/vehicle_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VehicleSpec.fromJson разбирает числа и переводит км/ч в м/с', () {
    final spec = VehicleSpec.fromJson({
      'maxSpeedKmh': 180.0,
      'acceleration': 10.0,
      'braking': 20.0,
    });

    expect(spec.maxSpeedKmh, 180.0);
    expect(spec.acceleration, 10.0);
    expect(spec.braking, 20.0);
    expect(spec.maxSpeedMs, closeTo(50.0, 1e-9)); // 180/3.6
  });
}
