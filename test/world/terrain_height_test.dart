import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:crime_oren/world/nav_grid.dart';
import 'package:crime_oren/world/terrain_height.dart';
import 'package:crime_oren/player/character_motion.dart';
import 'package:crime_oren/vehicles/vehicle_controller_component.dart';
import 'package:flutter_scene/scene.dart';

void main() {
  late TerrainHeight terrain;
  setUpAll(() {
    final cells = Uint8List(200 * 200);
    for (var z = 0; z < 200; z++) {
      cells[z * 200 + 99] = NavKind.sidewalk.index; // Even a 1 m path.
      for (var x = 140; x < 165 && z > 130 && z < 160; x++) {
        cells[z * 200 + x] = NavKind.building.index;
      }
    }
    terrain = TerrainHeight(
      NavGrid(
        minX: 0,
        minZ: 0,
        metersPerCell: 1,
        width: 200,
        height: 200,
        cells: cells,
      ),
    );
  });
  test('free ground rises, narrow paths and foundations remain at datum', () {
    expect(terrain.heightAt(45, 60), greaterThan(1));
    for (var z = 0.0; z < 200; z += .5) {
      expect(terrain.heightAt(99.5, z), 0);
    }
    expect(terrain.heightAt(150, 145), 0);
    expect(terrain.heightAt(-100, 0), 0);
  });
  test('terrain has walkable slopes and continuous cell boundaries', () {
    for (var x = 12.0; x < 180; x += .7) {
      final n = terrain.normalAt(x, 60);
      expect(n.y, greaterThan(.85));
      expect(
        (terrain.heightAt(x + .001, 60) - terrain.heightAt(x - .001, 60)).abs(),
        lessThan(.002),
      );
    }
  });
  test('camera arm detects a hill', () {
    final y = terrain.heightAt(45, 60);
    expect(
      terrain.cast(vm.Vector3(45, y + 1, 60), vm.Vector3(0, -1, 0), 3),
      inInclusiveRange(.6, 1),
    );
    expect(
      terrain.cast(vm.Vector3(45, y + 1, 60), vm.Vector3(0, 1, 0), 3),
      isNull,
    );
  });
  test('walking follows relief, including over an old flat OSM surface', () {
    final motion = CharacterMotion(
      position: vm.Vector3(45, terrain.heightAt(45, 60), 60),
      groundHeightAt: terrain.heightAt,
      raycast: (o, d, reach) => d.y < -.9 && o.y <= reach
          ? CharacterRayHit(distance: o.y, normal: vm.Vector3(0, 1, 0))
          : null,
    );
    motion.setMoveInput(vm.Vector2(0, 1));
    for (var i = 0; i < 600; i++) {
      motion.step(1 / 60);
      expect(
        (motion.position.y -
                terrain.heightAt(motion.position.x, motion.position.z))
            .abs(),
        lessThan(.06),
      );
    }
    expect(motion.position.z, greaterThan(75));
    motion.jump();
    for (var i = 0; i < 120; i++) {
      motion.step(1 / 60);
    }
    expect(motion.isGrounded, isTrue);
  });
  test('vehicle wheels tilt the body up a ramp', () {
    final node = Node();
    final controller = VehicleControllerComponent(
      maxSpeed: 45,
      acceleration: 8.2,
      braking: 10.5,
    )..groundHeightAt = (x, z) => z * 0.12;
    node.addComponent(controller);
    controller.setInput(throttle: 1, steer: 0);
    for (var i = 0; i < 120; i++) {
      controller.fixedUpdate(1 / 60);
    }
    final forward = node.localTransform.rotate3(vm.Vector3(0, 0, 1));
    expect(forward.y, closeTo(0.12 / 1.007174, .005));
  });
  test('vehicle base follows the four wheel support heights', () {
    final node = Node()
      ..position = vm.Vector3(45, terrain.heightAt(45, 60), 60);
    final controller = VehicleControllerComponent(
      maxSpeed: 45,
      acceleration: 8.2,
      braking: 10.5,
    )..groundHeightAt = terrain.heightAt;
    node.addComponent(controller);
    controller.setInput(throttle: 1, steer: 0);
    for (var i = 0; i < 180; i++) {
      controller.fixedUpdate(1 / 60);
      expect(node.position.y, closeTo(controller.groundContact!.height, .001));
    }
  });
}
