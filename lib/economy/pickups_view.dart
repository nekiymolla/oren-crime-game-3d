import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'pickups.dart';

/// Рисует [PickupField]: пачки денег (зелёные), патроны (латунь) и
/// бронежилеты (синие) —
/// покачиваются и крутятся, чтобы их было видно на траве и асфальте.
/// Один InstancedMesh на фиксированный пул; свободные места спрятаны.
class PickupsView {
  PickupsView(this.field)
    : _mesh = InstancedMesh(
        geometry: CuboidGeometry(vm.Vector3(0.34, 0.12, 0.2)),
        material: PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
          ..roughnessFactor = 0.5
          // Чуть светятся — заметны и ночью.
          ..emissiveFactor = vm.Vector4(0.25, 0.25, 0.25, 1)
          ..emissiveStrength = 1.0,
      ) {
    for (var i = 0; i < field.capacity; i++) {
      _mesh.addInstance(_hidden, color: _moneyColor);
    }
  }

  final PickupField field;
  final InstancedMesh _mesh;
  double _time = 0.0;

  static final vm.Vector4 _moneyColor = vm.Vector4(0.2, 0.75, 0.3, 1.0);
  static final vm.Vector4 _ammoColor = vm.Vector4(0.85, 0.65, 0.2, 1.0);
  static final vm.Vector4 _armorColor = vm.Vector4(0.25, 0.5, 1.0, 1.0);
  static final vm.Matrix4 _hidden = vm.Matrix4.compose(vm.Vector3(0, -50, 0), vm.Quaternion.identity(), vm.Vector3.all(0.01));

  Node buildNode() => Node()..addComponent(InstancedMeshComponent(_mesh));

  void update(double dt) {
    _time += dt;
    for (var i = 0; i < field.capacity; i++) {
      if (i >= field.items.length) {
        _mesh.setInstanceTransform(i, _hidden);
        continue;
      }
      final item = field.items[i];
      final phase = i * 1.7;
      final lift = 0.35 + 0.08 * math.sin(_time * 3.0 + phase);
      _mesh
        ..setInstanceColor(i, item.money > 0 ? _moneyColor : (item.armor > 0 ? _armorColor : _ammoColor))
        ..setInstanceTransform(
          i,
          vm.Matrix4.compose(
            item.position + vm.Vector3(0, lift, 0),
            vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), _time * 2.0 + phase),
            vm.Vector3.all(1.0),
          ),
        );
    }
  }
}
