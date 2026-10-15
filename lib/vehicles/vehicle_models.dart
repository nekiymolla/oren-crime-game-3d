import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'vehicle_damage.dart';

/// Модели машин (assets/models/vehicles, готовит
/// tools/assets/prepare_vehicles.mjs из Cars Bundle Quaternius, CC0).
///
/// Узлы модели: Body (кузов) и колёса Wheel_FL / Wheel_FR / Wheels_R
/// (задние — одна ось) с опорной точкой в центре колеса. Материалы
/// размечены ролями: Paint (перекрашивается), Glass, Headlights,
/// TailLights, Siren_White / Siren_Blue (мигалка полиции).
///
/// Глобальный [instance] — потому что сборка машины синхронная и
/// зовётся из многих мест (трафик, полиция, угон, см. vehicle.dart);
/// без загруженных моделей (тесты) машины остаются процедурными.
class VehicleModels {
  VehicleModels._(this._templates);

  static VehicleModels? instance;

  static const String modelsDir = 'assets/models/vehicles';
  static const List<String> ids = ['sedan', 'hatchback', 'suv', 'sports', 'sports2', 'taxi', 'police'];

  static const List<String> wheelNames = ['Wheel_FL', 'Wheel_FR', 'Wheels_R'];

  final Map<String, Node> _templates;

  static Future<void> load() async {
    final nodes = await Future.wait(ids.map((id) => loadScene('$modelsDir/$id.glb')));
    instance = VehicleModels._({for (var i = 0; i < ids.length; i++) ids[i]: nodes[i]});
  }

  bool has(String id) => _templates.containsKey(id);

  /// Кузов [id] в состоянии [level], крашеный в [paint] (если у модели есть
  /// материал Paint — у такси и полиции цвет фирменный).
  Node body(String id, DamageLevel level, vm.Vector4 paint) {
    final source = _templates[id]!.getChildByName('Body')!;
    final body = source.clone();
    final paintMaterial = _paint(paint, level);
    for (final primitive in body.mesh!.primitives) {
      final material = switch (primitive.material.name) {
        'Paint' => paintMaterial,
        'Glass' => level == DamageLevel.wrecked ? _brokenGlass : _glass,
        'Headlights' => level == DamageLevel.wrecked ? _brokenLight : headlightMaterial,
        'TailLights' => level == DamageLevel.wrecked ? _brokenLight : tailLightMaterial,
        'Siren_White' => sirenWhiteMaterial,
        'Siren_Blue' => sirenBlueMaterial,
        _ => null,
      };
      if (material != null) primitive.material = material;
    }
    return body;
  }

  /// Колёса [id] — клоны с опорной точкой в центре колеса.
  List<Node> wheels(String id) => [
    for (final name in wheelNames)
      if (_templates[id]!.getChildByName(name) case final wheel?) wheel.clone(),
  ];

  /// Краска: у целой — глянец с лаком, побитая темнее и матовее,
  /// сгоревшая — копоть.
  static PhysicallyBasedMaterial _paint(vm.Vector4 color, DamageLevel level) {
    final base = switch (level) {
      DamageLevel.pristine => color,
      DamageLevel.damaged => vm.Vector4(color.x * 0.6, color.y * 0.6, color.z * 0.6, 1.0),
      DamageLevel.wrecked => vm.Vector4(0.05, 0.05, 0.05, 1.0),
    };
    return PhysicallyBasedMaterial()
      ..baseColorFactor = base
      ..metallicFactor = level == DamageLevel.wrecked ? 0.1 : 0.5
      ..roughnessFactor = switch (level) {
        DamageLevel.pristine => 0.32,
        DamageLevel.damaged => 0.55,
        DamageLevel.wrecked => 0.85,
      }
      ..clearcoat = level == DamageLevel.pristine ? 1.0 : 0.0
      ..clearcoatRoughness = 0.08;
  }

  static final PhysicallyBasedMaterial _glass = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.04, 0.05, 0.07, 1.0)
    ..metallicFactor = 0.0
    ..roughnessFactor = 0.05;

  static final PhysicallyBasedMaterial _brokenGlass = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.35, 0.35, 0.38, 1.0)
    ..roughnessFactor = 0.6;

  static final PhysicallyBasedMaterial _brokenLight = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.25, 0.25, 0.25, 1.0)
    ..roughnessFactor = 0.9;

  /// Фары всех машин (общий материал: ночью включаются одной правкой, см.
  /// setHeadlightsGlow в vehicle.dart).
  static final PhysicallyBasedMaterial headlightMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(1.0, 0.98, 0.85, 1.0)
    ..emissiveFactor = vm.Vector4(1.0, 0.95, 0.7, 1.0)
    ..emissiveStrength = 2.0
    ..roughnessFactor = 0.3;

  static final PhysicallyBasedMaterial tailLightMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.6, 0.02, 0.02, 1.0)
    ..emissiveFactor = vm.Vector4(1.0, 0.05, 0.03, 1.0)
    ..emissiveStrength = 0.6
    ..roughnessFactor = 0.3;

  static final PhysicallyBasedMaterial sirenWhiteMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.9, 0.9, 0.95, 1.0)
    ..emissiveFactor = vm.Vector4(1.0, 0.1, 0.08, 1.0)
    ..roughnessFactor = 0.3;

  static final PhysicallyBasedMaterial sirenBlueMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.1, 0.2, 0.9, 1.0)
    ..emissiveFactor = vm.Vector4(0.1, 0.25, 1.0, 1.0)
    ..roughnessFactor = 0.3;

  /// Мигалка всех патрульных машин: красный и синий по очереди (общие
  /// материалы — одна правка на кадр, сколько бы машин ни было).
  static void updateSirens(double timeSeconds) {
    final phase = (timeSeconds * 2.5) % 1.0;
    final redOn = phase < 0.5;
    // Двойная вспышка внутри своей половины — как у настоящей мигалки.
    final local = (phase % 0.5) / 0.5;
    final flash = local < 0.3 || (local > 0.45 && local < 0.75) ? 1.0 : 0.15;
    sirenWhiteMaterial.emissiveStrength = redOn ? 8.0 * flash : 0.3;
    sirenBlueMaterial.emissiveStrength = redOn ? 0.3 : 8.0 * flash;
  }
}

/// Колёса крутятся и рулят по движению самого узла машины: годится и для
/// машины игрока, и для трафика, который двигают позицией без контроллера.
/// Руль — по велосипедной модели из скорости поворота курса.
class WheelSpinComponent extends Component {
  WheelSpinComponent(this.wheels, {required this.wheelRadius, required this.wheelbase})
    : _bases = [for (final wheel in wheels) wheel.position];

  /// Колёса в порядке [VehicleModels.wheelNames]: передние — первые два.
  final List<Node> wheels;
  final double wheelRadius;
  final double wheelbase;
  final List<vm.Vector3> _bases;

  vm.Vector3? _lastPosition;
  double _lastYaw = 0.0;
  double _spin = 0.0;
  double _steer = 0.0;

  static const double _maxSteer = 0.55;

  @override
  void update(double deltaSeconds) {
    if (deltaSeconds <= 0) return;
    final transform = node.globalTransform;
    final position = transform.getTranslation();
    // Курс — куда смотрит локальная +Z (перед машины).
    final forward = transform.transform3(vm.Vector3(0, 0, 1)) - position;
    final yaw = math.atan2(forward.x, forward.z);
    final last = _lastPosition;
    _lastPosition = position;
    if (last == null) {
      _lastYaw = yaw;
      return;
    }
    final delta = position - last;
    // Скачок (телепорт, переселение трафика) — не езда.
    if (delta.length > 10.0) {
      _lastYaw = yaw;
      return;
    }
    final along = delta.x * math.sin(yaw) + delta.z * math.cos(yaw);
    final speed = along / deltaSeconds;
    final yawRate = _wrap(yaw - _lastYaw) / deltaSeconds;
    _lastYaw = yaw;

    _spin = (_spin + along / wheelRadius) % (2 * math.pi);
    final targetSteer = speed.abs() > 0.5
        ? math.atan(wheelbase * yawRate / speed).clamp(-_maxSteer, _maxSteer)
        : _steer;
    _steer += (targetSteer - _steer) * (1.0 - math.exp(-8.0 * deltaSeconds));

    final roll = vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), _spin);
    for (var i = 0; i < wheels.length; i++) {
      final front = i < 2 && wheels.length == 3;
      wheels[i]
        ..position = _bases[i]
        ..rotation = front ? vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _steer) * roll : roll;
    }
  }

  static double _wrap(double angle) => (angle + math.pi) % (2 * math.pi) - math.pi;
}
