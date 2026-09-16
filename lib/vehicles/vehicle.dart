import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'vehicle_controller_component.dart';
import 'vehicle_input_bridge_component.dart';

/// Процедурный плейсхолдер седана — низкий кузов + кабина сверху со сдвигом
/// к корме (силуэт седана, а не сплошной "контейнер") + 4 колеса + фары.
/// Настоящая 3D-модель — отдельная задача, здесь только геометрия на время
/// её отсутствия. Разгон/торможение/руление заданы в assets/data/vehicles.json
/// (car_sedan_01) — здесь только геометрия.
class BuiltVehicle {
  BuiltVehicle({required this.node, required this.controller});

  /// Узел-машина — точка контакта с землёй (как и у игрока), тот же паттерн:
  /// origin на уровне земли, меши смещены вверх дочерними узлами.
  final Node node;
  final VehicleControllerComponent controller;
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

  final paintMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.12, 0.32, 0.62, 1.0)
    ..metallicFactor = 0.6
    ..roughnessFactor = 0.35;

  final chassis = Node(
    mesh: Mesh(CuboidGeometry(vm.Vector3(bodyWidth, chassisHeight, bodyLength)), paintMaterial),
  )..position = vm.Vector3(0, wheelRadius + chassisHeight / 2, 0);
  node.add(chassis);

  final cabinMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.05, 0.06, 0.08, 1.0)
    ..metallicFactor = 0.1
    ..roughnessFactor = 0.15;
  final cabin = Node(
    mesh: Mesh(CuboidGeometry(vm.Vector3(cabinWidth, cabinHeight, cabinLength)), cabinMaterial),
  )..position = vm.Vector3(
      0,
      wheelRadius + chassisHeight + cabinHeight / 2,
      cabinZOffset,
    );
  node.add(cabin);

  final headlightMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(1.0, 0.98, 0.85, 1.0)
    ..emissiveFactor = vm.Vector4(1.0, 0.95, 0.7, 1.0)
    ..emissiveStrength = 2.0
    ..roughnessFactor = 0.3;
  const headlightSize = 0.14;
  for (final side in [-1, 1]) {
    final headlight = Node(
      mesh: Mesh(
        CuboidGeometry(vm.Vector3(headlightSize, headlightSize, 0.05)),
        headlightMaterial,
      ),
    )..position = vm.Vector3(
        side * (bodyWidth / 2 - headlightSize),
        wheelRadius + chassisHeight / 2,
        bodyLength / 2,
      );
    node.add(headlight);
  }

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
    maxSpeed: 45.8, // 165 км/ч из vehicles.json car_sedan_01
    acceleration: 8.2,
    braking: 10.5,
    groundPlaneHeight: 0.0,
    bodyHalfWidth: bodyWidth / 2,
    bodyHalfLength: bodyLength / 2,
  );
  node
    ..addComponent(controller)
    ..addComponent(VehicleInputBridgeComponent(controller));

  return BuiltVehicle(node: node, controller: controller);
}
