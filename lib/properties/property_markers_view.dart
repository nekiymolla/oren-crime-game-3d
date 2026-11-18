import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'property.dart';

/// A quiet ground marker at the entrance. The map and nearby interaction
/// label explain the property; no floating emissive cube blocks the camera.
class PropertyMarkersView {
  PropertyMarkersView(this.system);

  final PropertySystem system;
  final List<({PropertyConfig property, PhysicallyBasedMaterial material})>
  _markers = [];

  static final vm.Vector4 _forSale = vm.Vector4(0.12, 0.32, 0.21, 1.0);
  static final vm.Vector4 _owned = vm.Vector4(0.12, 0.25, 0.38, 1.0);

  Node buildNode() {
    final root = Node();
    final geometry = CylinderGeometry(
      bottomRadius: 0.65,
      topRadius: 0.65,
      height: 0.015,
      radialSegments: 32,
    );
    for (final property in system.properties) {
      final material = PhysicallyBasedMaterial()
        ..roughnessFactor = 0.95
        ..emissiveStrength = 0.15;
      root.add(
        Node(mesh: Mesh(geometry, material))
          ..position = property.entryPoint + vm.Vector3(0, 0.025, 0),
      );
      _markers.add((property: property, material: material));
    }
    update(0);
    return root;
  }

  void update(double dt) {
    for (final marker in _markers) {
      final color = system.isOwned(marker.property) ? _owned : _forSale;
      marker.material
        ..baseColorFactor = color
        ..emissiveFactor = color;
    }
  }
}
