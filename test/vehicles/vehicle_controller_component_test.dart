import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crime_oren/vehicles/vehicle_controller_component.dart';

void main() {
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

  // Столкновения (raycastNode против реальной геометрии стены) юнит-тестом
  // не проверить headless: CuboidGeometry сразу грузит вершины в GPU при
  // конструировании (Flutter GPU требует Impeller-контекст), которого нет
  // в `flutter test`. Эта часть проверяется только вживую в игре.
}
