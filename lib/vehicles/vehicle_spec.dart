import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Характеристики вождения одной машины из assets/data/vehicles.json —
/// только поля, которые реально читает VehicleControllerComponent. Файл
/// содержит и другие поля (движок, подвеска, топливо, звуки) — заготовки
/// под системы, которых ещё нет, читать их сейчас незачем.
class VehicleSpec {
  const VehicleSpec({
    required this.maxSpeedKmh,
    required this.acceleration,
    required this.braking,
    this.mass = 1450,
    this.tyreFriction = 1.0,
  });

  factory VehicleSpec.fromJson(Map<String, dynamic> json) => VehicleSpec(
    maxSpeedKmh: (json['maxSpeedKmh'] as num).toDouble(),
    acceleration: (json['acceleration'] as num).toDouble(),
    braking: (json['braking'] as num).toDouble(),
    mass: (json['mass'] as num?)?.toDouble() ?? 1450,
    tyreFriction:
        ((json['wheels'] as Map?)?['gripFriction'] as num?)?.toDouble() ?? 1.0,
  );

  final double maxSpeedKmh;
  final double acceleration;
  final double braking;
  final double mass, tyreFriction;

  double get maxSpeedMs => maxSpeedKmh / 3.6;
}

/// Ищет [id] среди `vehicles` в assets/data/vehicles.json. `null`, если
/// файла/записи нет — вызывающая сторона решает, каким значением по
/// умолчанию заменить (см. buildVehicle в vehicle.dart).
Future<VehicleSpec?> loadVehicleSpec(String id) async {
  final raw = await rootBundle.loadString('assets/data/vehicles.json');
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final vehicles = json['vehicles'] as List;
  for (final entry in vehicles) {
    final map = entry as Map<String, dynamic>;
    if (map['id'] == id) return VehicleSpec.fromJson(map);
  }
  return null;
}
