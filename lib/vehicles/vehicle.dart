import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'vehicle_controller_component.dart';
import 'vehicle_damage.dart';
import 'vehicle_input_bridge_component.dart';

/// Процедурный плейсхолдер седана — низкий кузов + кабина сверху со сдвигом
/// к корме (силуэт седана, а не сплошной "контейнер") + 4 колеса + фары.
/// Настоящая 3D-модель — отдельная задача, здесь только геометрия на время
/// её отсутствия. Разгон/торможение/руление заданы в assets/data/vehicles.json
/// (car_sedan_01) — здесь только геометрия.
///
/// Три визуальных состояния кузова (см. [DamageLevel]) — не настоящая
/// деформация, а переключение видимости между тремя заранее построенными
/// preset-узлами (pristine/damaged/wrecked), как и было задумано в
/// PROGRESS.md (полноценная деформация ждёт rigid-body физики — см. решение
/// про flutter_scene_rapier там же).
class BuiltVehicle {
  BuiltVehicle({
    required this.node,
    required this.controller,
    required this.damage,
    required Map<DamageLevel, Node> bodyVariants,
  }) : _bodyVariants = bodyVariants {
    _syncVisibility();
    controller.onCollision = (impactSpeed) {
      damage.registerCollision(impactSpeed);
      _syncVisibility();
    };
  }

  /// Узел-машина — точка контакта с землёй (как и у игрока), тот же паттерн:
  /// origin на уровне земли, меши смещены вверх дочерними узлами.
  final Node node;
  final VehicleControllerComponent controller;
  final VehicleDamageState damage;
  final Map<DamageLevel, Node> _bodyVariants;

  DamageLevel? _visibleLevel;

  void _syncVisibility() {
    final level = damage.level;
    if (level == _visibleLevel) return;
    for (final entry in _bodyVariants.entries) {
      entry.value.visible = entry.key == level;
    }
    _visibleLevel = level;
  }
}

BuiltVehicle buildPlaceholderSedan() {
  const bodyWidth = 1.8;
  const chassisHeight = 0.65;
  const bodyLength = 4.4;
  const cabinHeight = 0.62;
  const cabinLength = 2.3;
  const cabinWidth = bodyWidth * 0.86;
  const cabinZOffset = -0.35; // сдвиг кабины к корме — силуэт седана
  const wheelRadius = 0.33;
  const wheelWidth = 0.22;

  final node = Node();

  final bodyVariants = {
    for (final level in DamageLevel.values)
      level: _buildBodyVariant(
        level,
        bodyWidth: bodyWidth,
        chassisHeight: chassisHeight,
        bodyLength: bodyLength,
        cabinHeight: cabinHeight,
        cabinLength: cabinLength,
        cabinWidth: cabinWidth,
        cabinZOffset: cabinZOffset,
        wheelRadius: wheelRadius,
      ),
  };
  bodyVariants.values.forEach(node.add);

  final wheelMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.05, 0.05, 0.05, 1.0)
    ..roughnessFactor = 0.9;
  final wheelRotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), math.pi / 2);

  final wheelOffsets = [
    vm.Vector3(bodyWidth / 2, wheelRadius, bodyLength / 2 - wheelRadius * 1.4),
    vm.Vector3(-bodyWidth / 2, wheelRadius, bodyLength / 2 - wheelRadius * 1.4),
    vm.Vector3(bodyWidth / 2, wheelRadius, -bodyLength / 2 + wheelRadius * 1.4),
    vm.Vector3(-bodyWidth / 2, wheelRadius, -bodyLength / 2 + wheelRadius * 1.4),
  ];
  for (final offset in wheelOffsets) {
    final wheel = Node(
      mesh: Mesh(
        CylinderGeometry(
          bottomRadius: wheelRadius,
          topRadius: wheelRadius,
          height: wheelWidth,
        ),
        wheelMaterial,
      ),
    )
      ..position = offset
      ..rotation = wheelRotation;
    node.add(wheel);
  }

  final controller = VehicleControllerComponent(
    maxSpeed: 55.6, // 200 км/ч — быстрее прежних 165 (см. PROGRESS.md)
    acceleration: 16.0, // было 8.2 — разгон ощущался вялым
    braking: 32.0, // было 10.5 — торможение тянулось неприлично долго
    groundPlaneHeight: 0.0,
    bodyHalfWidth: bodyWidth / 2,
    bodyHalfLength: bodyLength / 2,
  );
  node
    ..addComponent(controller)
    ..addComponent(VehicleInputBridgeComponent(controller));

  return BuiltVehicle(
    node: node,
    controller: controller,
    damage: VehicleDamageState(),
    bodyVariants: bodyVariants,
  );
}

/// Кузов+кабина+фары под один [DamageLevel]. Колёса не варьируются —
/// одинаковые для всех уровней, строятся отдельно в [buildPlaceholderSedan].
Node _buildBodyVariant(
  DamageLevel level, {
  required double bodyWidth,
  required double chassisHeight,
  required double bodyLength,
  required double cabinHeight,
  required double cabinLength,
  required double cabinWidth,
  required double cabinZOffset,
  required double wheelRadius,
}) {
  final variant = Node();

  final paintColor = switch (level) {
    DamageLevel.pristine => vm.Vector4(0.12, 0.32, 0.62, 1.0),
    DamageLevel.damaged => vm.Vector4(0.10, 0.20, 0.38, 1.0), // помятая, тусклее
    DamageLevel.wrecked => vm.Vector4(0.05, 0.05, 0.05, 1.0), // копоть/ржавчина
  };
  final paintMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = paintColor
    ..metallicFactor = level == DamageLevel.wrecked ? 0.1 : 0.6
    ..roughnessFactor = switch (level) {
      DamageLevel.pristine => 0.35,
      DamageLevel.damaged => 0.55,
      DamageLevel.wrecked => 0.8,
    };

  final chassis = Node(
    mesh: Mesh(CuboidGeometry(vm.Vector3(bodyWidth, chassisHeight, bodyLength)), paintMaterial),
  )..position = vm.Vector3(0, wheelRadius + chassisHeight / 2, 0);
  variant.add(chassis);

  // Кабина: у wrecked стекло-материал светлее и матовее — "разбитое"
  // вместо чистого тонированного стекла у pristine/damaged.
  final cabinColor = level == DamageLevel.wrecked
      ? vm.Vector4(0.35, 0.35, 0.38, 1.0)
      : vm.Vector4(0.05, 0.06, 0.08, 1.0);
  final cabinMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = cabinColor
    ..metallicFactor = 0.1
    ..roughnessFactor = level == DamageLevel.wrecked ? 0.6 : 0.15;
  final cabin = Node(
    mesh: Mesh(CuboidGeometry(vm.Vector3(cabinWidth, cabinHeight, cabinLength)), cabinMaterial),
  )..position = vm.Vector3(
      0,
      wheelRadius + chassisHeight + cabinHeight / 2,
      cabinZOffset,
    );
  variant.add(cabin);

  // Фары: damaged — левая разбита, wrecked — обе.
  final workingHeadlightMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(1.0, 0.98, 0.85, 1.0)
    ..emissiveFactor = vm.Vector4(1.0, 0.95, 0.7, 1.0)
    ..emissiveStrength = 2.0
    ..roughnessFactor = 0.3;
  final brokenHeadlightMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.25, 0.25, 0.25, 1.0)
    ..roughnessFactor = 0.9;
  const headlightSize = 0.14;
  for (final side in [-1, 1]) {
    final broken = level == DamageLevel.wrecked || (level == DamageLevel.damaged && side < 0);
    final headlight = Node(
      mesh: Mesh(
        CuboidGeometry(vm.Vector3(headlightSize, headlightSize, 0.05)),
        broken ? brokenHeadlightMaterial : workingHeadlightMaterial,
      ),
    )..position = vm.Vector3(
        side * (bodyWidth / 2 - headlightSize),
        wheelRadius + chassisHeight / 2,
        bodyLength / 2,
      );
    variant.add(headlight);
  }

  // Смятый бампер — тёмный кубик поверх переднего края, крупнее у wrecked.
  // Не настоящая деформация меша (см. doc-комментарий класса), но читается
  // как урон при взгляде на машину, а не только по смене цвета краски.
  if (level != DamageLevel.pristine) {
    final crumpleSize = level == DamageLevel.wrecked ? 0.5 : 0.25;
    final crumpleMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.08, 0.08, 0.08, 1.0)
      ..roughnessFactor = 0.95;
    final crumple = Node(
      mesh: Mesh(
        CuboidGeometry(vm.Vector3(bodyWidth * 0.9, chassisHeight * 0.7, crumpleSize)),
        crumpleMaterial,
      ),
    )..position = vm.Vector3(
        0,
        wheelRadius + chassisHeight / 2,
        bodyLength / 2 - crumpleSize / 2,
      );
    variant.add(crumple);
  }

  return variant;
}
