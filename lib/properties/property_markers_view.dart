import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'property.dart';

/// Маркеры у входов в дома: светящееся кольцо на земле и вращающийся
/// "домик" над ним. Зелёный — продаётся, голубой — свой.
class PropertyMarkersView {
  PropertyMarkersView(this.system);

  final PropertySystem system;
  final List<({PropertyConfig property, Node icon, PhysicallyBasedMaterial ring, PhysicallyBasedMaterial iconMaterial})> _markers = [];
  double _time = 0.0;

  static final vm.Vector4 _forSale = vm.Vector4(0.25, 1.0, 0.45, 1.0);
  static final vm.Vector4 _owned = vm.Vector4(0.3, 0.6, 1.0, 1.0);

  Node buildNode() {
    final root = Node();
    final ringGeometry = CylinderGeometry(bottomRadius: 1.0, topRadius: 1.0, height: 0.06, radialSegments: 24);
    final iconGeometry = CuboidGeometry(vm.Vector3(0.45, 0.45, 0.45));
    for (final property in system.properties) {
      final ring = _glow();
      final iconMaterial = _glow();
      final ringNode = Node(mesh: Mesh(ringGeometry, ring))..position = property.entryPoint + vm.Vector3(0, 0.04, 0);
      final icon = Node(mesh: Mesh(iconGeometry, iconMaterial));
      root
        ..add(ringNode)
        ..add(icon);
      _markers.add((property: property, icon: icon, ring: ring, iconMaterial: iconMaterial));
    }
    update(0);
    return root;
  }

  static PhysicallyBasedMaterial _glow() => PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.05, 0.05, 0.05, 1)
    ..emissiveStrength = 2.5;

  void update(double dt) {
    _time += dt;
    for (final marker in _markers) {
      final color = system.isOwned(marker.property) ? _owned : _forSale;
      marker.ring.emissiveFactor = color * 0.6;
      marker.iconMaterial.emissiveFactor = color;
      marker.icon.localTransform = vm.Matrix4.compose(
        marker.property.entryPoint + vm.Vector3(0, 1.4 + 0.12 * math.sin(_time * 2.0), 0),
        vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _time * 1.2) * vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 4),
        vm.Vector3.all(1.0),
      );
    }
  }
}
