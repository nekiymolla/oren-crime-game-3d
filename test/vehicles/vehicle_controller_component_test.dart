import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:crime_oren/world/tree_collision.dart';
import 'package:crime_oren/player/character_motion.dart';

import 'package:crime_oren/vehicles/vehicle_controller_component.dart';

void main() {
  test(
    'glancing wall contact retains tangential speed and uses local collider field',
    () {
      final node = Node();
      final car = VehicleControllerComponent(
        maxSpeed: 45,
        acceleration: 5.2,
        braking: 9.6,
      );
      node.addComponent(car);
      car.velocityXZ.setValues(5, 20);
      var prepared = 0, casts = 0;
      var impact = 0.0;
      car.prepareObstacles = (_) => prepared++;
      car.obstacleRaycast = (_, _, _) {
        casts++;
        return CharacterRayHit(distance: 0, normal: vm.Vector3(-1, 0, 0));
      };
      car.onCollision = (speed) => impact = speed;
      car.fixedUpdate(1 / 60);
      expect(prepared, 1);
      expect(casts, greaterThanOrEqualTo(4));
      expect(car.velocityXZ.x.abs(), lessThan(.001));
      expect(car.velocityXZ.y, greaterThan(10));
      expect(impact, lessThan(8));
    },
  );

  test('газ разгоняет машину вперёд по +Z', () {
    final node = Node();
    final controller = VehicleControllerComponent(
      maxSpeed: 45.0,
      acceleration: 8.2,
      braking: 10.5,
      groundPlaneHeight: 0.0,
    );
    node.addComponent(controller);

    controller.setInput(throttle: 1.0, steer: 0.0);
    for (var i = 0; i < 60; i++) {
      controller.fixedUpdate(1 / 60);
    }

    expect(controller.speed, greaterThan(0.0));
    expect(node.position.z, greaterThan(0.0));
    expect(node.position.x.abs(), lessThan(0.01)); // без руля едет прямо
  });

  test('руль разворачивает машину на ходу', () {
    final node = Node();
    final controller = VehicleControllerComponent(
      maxSpeed: 45.0,
      acceleration: 8.2,
      braking: 10.5,
      groundPlaneHeight: 0.0,
    );
    node.addComponent(controller);

    controller.setInput(throttle: 1.0, steer: 1.0);
    for (var i = 0; i < 120; i++) {
      controller.fixedUpdate(1 / 60);
    }

    // При руле вправо и движении вперёд машину должно снести/повернуть в +X.
    expect(node.position.x, greaterThan(0.0));
  });

  test('без газа машина тормозит накатом до нуля', () {
    final node = Node();
    final controller = VehicleControllerComponent(
      maxSpeed: 45.0,
      acceleration: 8.2,
      braking: 10.5,
      drag: 3.0,
      groundPlaneHeight: 0.0,
    );
    node.addComponent(controller);

    controller.setInput(throttle: 1.0, steer: 0.0);
    for (var i = 0; i < 60; i++) {
      controller.fixedUpdate(1 / 60);
    }
    final speedAfterThrottle = controller.speed;
    expect(speedAfterThrottle, greaterThan(0.0));

    controller.setInput(throttle: 0.0, steer: 0.0);
    for (var i = 0; i < 600; i++) {
      controller.fixedUpdate(1 / 60);
    }

    expect(controller.speed, closeTo(0.0, 0.01));
  });

  test('полный руль на скорости ограничивает боковое ускорение', () {
    final node = Node();
    final car = VehicleControllerComponent(
      maxSpeed: 55,
      acceleration: 8,
      braking: 12,
    );
    node.addComponent(car);
    car.velocityXZ.setValues(0, 30);
    car.setInput(throttle: 0, steer: 1);
    car.fixedUpdate(1 / 60);
    // Instantaneous full lock used to rotate the car by ~7 degrees/frame.
    expect(car.heading.abs(), lessThan(0.01));
    expect(car.steeringAngle.abs(), lessThan(0.03));
  });

  test('на парковочной скорости сохраняется полный выворот', () {
    final node = Node();
    final car = VehicleControllerComponent(
      maxSpeed: 55,
      acceleration: 8,
      braking: 12,
    );
    node.addComponent(car);
    car.setInput(throttle: 0, steer: 1);
    for (var i = 0; i < 120; i++) {
      car.fixedUpdate(1 / 60);
    }
    expect(car.steeringAngle, closeTo(car.maxSteerAngle, 0.001));
    car.setInput(throttle: 0, steer: 0);
    for (var i = 0; i < 60; i++) {
      car.fixedUpdate(1 / 60);
    }
    expect(car.steeringAngle.abs(), lessThan(0.001));
  });

  test('машина останавливается перед узким стволом и может отъехать назад', () {
    final node = Node()..position = vm.Vector3(0, 0, -8);
    final car = VehicleControllerComponent(
      maxSpeed: 45,
      acceleration: 8,
      braking: 12,
    );
    node.addComponent(car);
    car.additionalObstacleSweep = (origin, direction, distance, radius) =>
        raycastTreeTrunk(
          origin: origin,
          direction: direction,
          maxDistance: distance,
          root: vm.Vector3(0.45, 0, 0),
          sweepRadius: radius,
        )?.distance;
    car.setInput(throttle: 1, steer: 0);
    for (var i = 0; i < 240; i++) {
      car.fixedUpdate(1 / 60);
    }
    expect(node.position.z, lessThan(-car.bodyHalfLength));
    expect(car.speed, lessThan(0.1));
    final stoppedZ = node.position.z;
    car.setInput(throttle: -1, steer: 0);
    for (var i = 0; i < 120; i++) {
      car.fixedUpdate(1 / 60);
    }
    expect(node.position.z, lessThan(stoppedZ - 1));
  });

  // Столкновения (raycastNode против реальной геометрии стены) юнит-тестом
  // не проверить headless: CuboidGeometry сразу грузит вершины в GPU при
  // конструировании (Flutter GPU требует Impeller-контекст), которого нет
  // в `flutter test`. Эта часть проверяется только вживую в игре.
}
