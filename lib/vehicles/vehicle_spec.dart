import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Driving parameters are model-specific and shared by owned/stolen cars.
class VehicleSpec {
  const VehicleSpec({
    required this.maxSpeedKmh,
    required this.acceleration,
    required this.braking,
    this.mass = 1450,
    this.tyreFriction = 1,
    this.maxSteerAngle = .52,
    this.steeringResponse = 4,
    this.maxLateralAcceleration = 6.2,
    this.frontStiffness = 40,
    this.rearStiffness = 58,
    this.stabilityAssist = 1.2,
    this.driveBias = .35,
    this.rollCompliance = .009,
    this.pitchCompliance = .007,
    this.suspensionDamping = 11,
    this.restitution = .12,
    this.collisionFriction = .28,
    this.suspensionTravel = .18,
  });
  factory VehicleSpec.fromJson(Map<String, dynamic> json) {
    final h = json['handling'] as Map? ?? const {};
    final suspension = json['suspension'] as Map? ?? const {};
    double value(String key, double fallback) =>
        (h[key] as num?)?.toDouble() ?? fallback;
    return VehicleSpec(
      maxSpeedKmh: (json['maxSpeedKmh'] as num).toDouble(),
      acceleration: (json['acceleration'] as num).toDouble(),
      braking: (json['braking'] as num).toDouble(),
      mass: (json['mass'] as num?)?.toDouble() ?? 1450,
      tyreFriction:
          ((json['wheels'] as Map?)?['gripFriction'] as num?)?.toDouble() ?? 1,
      maxSteerAngle: value('maxSteerAngle', .52),
      steeringResponse: value('steeringResponse', 4),
      maxLateralAcceleration: value('maxLateralAcceleration', 6.2),
      frontStiffness: value('frontStiffness', 40),
      rearStiffness: value('rearStiffness', 58),
      stabilityAssist: value('stabilityAssist', 1.2),
      driveBias: value('driveBias', .35),
      rollCompliance: value('rollCompliance', .009),
      pitchCompliance: value('pitchCompliance', .007),
      suspensionDamping: value('suspensionDamping', 11),
      restitution: value('restitution', .12),
      collisionFriction: value('collisionFriction', .28),
      suspensionTravel: (suspension['travel'] as num?)?.toDouble() ?? .18,
    );
  }
  final double maxSpeedKmh, acceleration, braking, mass, tyreFriction;
  final double maxSteerAngle,
      steeringResponse,
      maxLateralAcceleration,
      frontStiffness,
      rearStiffness,
      stabilityAssist,
      driveBias,
      rollCompliance,
      pitchCompliance,
      suspensionDamping,
      restitution,
      collisionFriction,
      suspensionTravel;
  double get maxSpeedMs => maxSpeedKmh / 3.6;
}

Map<String, VehicleSpec> _byId = {}, _byModel = {};
Future<void>? _loading;
Future<void> loadVehicleCatalog() => _loading ??= _loadCatalog();
Future<void> _loadCatalog() async {
  final json =
      jsonDecode(await rootBundle.loadString('assets/data/vehicles.json'))
          as Map<String, dynamic>;
  final byId = <String, VehicleSpec>{}, byModel = <String, VehicleSpec>{};
  for (final raw in json['vehicles'] as List) {
    final entry = raw as Map<String, dynamic>, spec = VehicleSpec.fromJson(raw);
    byId[entry['id'] as String] = spec;
    final model = entry['modelId'] as String?;
    if (model != null) byModel[model] = spec;
  }
  _byId = byId;
  _byModel = byModel;
}

VehicleSpec? vehicleSpecForModel(String? model) => _byModel[model];
Future<VehicleSpec?> loadVehicleSpec(String id) async {
  await loadVehicleCatalog();
  return _byId[id];
}
