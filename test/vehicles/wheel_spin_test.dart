import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:crime_oren/vehicles/vehicle_models.dart';

void main() {
  for (final count in [3, 4]) {
    test('$count wheel nodes: front wheels steer, rear wheels only roll', () {
      final root = Node();
      final wheels = List.generate(
        count,
        (i) => Node()
          ..position = vm.Vector3(
            i.isEven ? 0.72 : -0.72,
            0.3,
            i < 2 ? 1.35 : -1.3,
          ),
      );
      wheels.forEach(root.add);
      final spin = WheelSpinComponent(
        wheels,
        wheelRadius: 0.3,
        wheelbase: 2.65,
      );
      root.addComponent(spin);
      spin.update(1 / 60);
      root
        ..position = vm.Vector3(0, 0, 0.2)
        ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), 0.03);
      spin.update(1 / 60);
      for (var i = 0; i < count; i++) {
        expect(wheels[i].rotation.x.abs(), greaterThan(0.01));
        if (i < 2) {
          expect(wheels[i].rotation.y.abs(), greaterThan(0.001));
        } else {
          expect(wheels[i].rotation.y.abs(), lessThan(1e-6));
        }
      }
    });
  }
}
