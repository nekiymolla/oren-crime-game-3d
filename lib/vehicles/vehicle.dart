import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'vehicle_controller_component.dart';
import 'vehicle_input_bridge_component.dart';

/// Процедурный плейсхолдер седана (кузов-параллелепипед + 4 цилиндра-колеса)
/// на время, пока нет настоящей 3D-модели машины. Разгон/торможение/руление
/// заданы в assets/data/vehicles.json (car_sedan_01) — здесь только геометрия.
class BuiltVehicle {
  BuiltVehicle({required this.node, required this.controller});

  /// Узел-машина — точка контакта с землёй (как и у игрока), тот же паттерн:
  /// origin на уровне земли, меши смещены вверх дочерними узлами.
  final Node node;
  final VehicleControllerComponent controller;
}

BuiltVehicle buildPlaceholderSedan() {
  const bodyWidth = 1.8;
  const bodyHeight = 1.3;
  const bodyLength = 4.4;
  const wheelRadius = 0.33;
  const wheelWidth = 0.22;

  final node = Node();

  final bodyMesh = Node(
    mesh: Mesh(
      CuboidGeometry(vm.Vector3(bodyWidth, bodyHeight, bodyLength)),
      PhysicallyBasedMaterial()
        ..baseColorFactor = vm.Vector4(0.12, 0.32, 0.62, 1.0)
        ..metallicFactor = 0.6
        ..roughnessFactor = 0.35,
    ),
  )..position = vm.Vector3(0, wheelRadius + bodyHeight / 2, 0);
  node.add(bodyMesh);

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
  );
  node
    ..addComponent(controller)
    ..addComponent(VehicleInputBridgeComponent(controller));

  return BuiltVehicle(node: node, controller: controller);
}
