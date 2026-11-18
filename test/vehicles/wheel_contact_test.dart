import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:crime_oren/vehicles/wheel_contact.dart';
import 'package:crime_oren/vehicles/vehicle_controller_component.dart';

void main() {
  final anchors = [
    vm.Vector3(-.72, 0, 1.38),
    vm.Vector3(.72, 0, 1.38),
    vm.Vector3(-.72, 0, -1.27),
    vm.Vector3(.72, 0, -1.27),
  ];
  test('four contacts fit a slope despite an asymmetric axle placement', () {
    for (final heading in [0.0, .7, 2.4]) {
      final contact = WheelContact.sample(
        x: 10,
        z: 20,
        heading: heading,
        anchors: anchors,
        heightAt: (x, z) => 1 + .1 * x + .05 * z,
      );
      expect(contact.height, closeTo(3, .00001));
    }
  });
  test(
    'a small bump under the centre does not lift four tyres off the ground',
    () {
      final c = WheelContact.sample(
        x: 0,
        z: 0,
        heading: 0,
        anchors: anchors,
        heightAt: (x, z) => x.abs() < .2 && z.abs() < .2 ? .1 : 0,
      );
      expect(c.height, 0);
      expect(c.pitch, 0);
      expect(c.roll, 0);
    },
  );
  test(
    'individual wheels follow a one-wheel bump within suspension travel',
    () {
      double height(double x, double z) => x < 0 && z > 0 ? .12 : 0;
      final node = Node();
      final wheels = [
        for (final p in anchors) Node()..position = vm.Vector3(p.x, .3, p.z),
      ];
      for (final w in wheels) {
        node.add(w);
      }
      final car = VehicleControllerComponent(
        maxSpeed: 45,
        acceleration: 5.2,
        braking: 9.6,
      )..groundHeightAt = height;
      car.configureWheels(wheels);
      node.addComponent(car);
      for (var i = 0; i < 240; i++) {
        car.fixedUpdate(1 / 60);
      }
      final displacements = <double>[];
      for (final w in wheels) {
        final center = node.globalTransform.transform3(w.position.clone());
        expect(center.y - .3, closeTo(height(center.x, center.z), .0001));
        displacements.add(w.position.y - .3);
      }
      expect(displacements.any((d) => d > .01), isTrue);
      expect(displacements.any((d) => d < -.01), isTrue);
    },
  );
}
