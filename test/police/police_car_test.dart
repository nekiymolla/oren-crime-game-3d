import 'dart:math' as math;

import 'package:crime_oren/police/police_car.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('цель точно впереди по курсу — руль почти нулевой, полный газ', () {
    final input = computePoliceInput(
      position: vm.Vector3(0, 0, 0),
      heading: 0.0, // курс на +Z
      targetPosition: vm.Vector3(0, 0, 10), // цель тоже по +Z
    );
    expect(input.steer, closeTo(0.0, 1e-9));
    expect(input.throttle, 1.0);
  });

  test('цель сбоку — руль в сторону цели, газ снижен на крутом развороте', () {
    final input = computePoliceInput(
      position: vm.Vector3(0, 0, 0),
      heading: 0.0,
      targetPosition: vm.Vector3(10, 0, 0), // цель строго вправо (+X)
    );
    expect(input.steer, greaterThan(0.0));
    expect(input.throttle, lessThan(1.0));
  });

  test('цель сзади — руль в сторону короткой дуги (не всегда в одну сторону)', () {
    final input = computePoliceInput(
      position: vm.Vector3(0, 0, 0),
      heading: 0.0,
      targetPosition: vm.Vector3(0, 0, -10), // цель строго позади
    );
    expect(input.steer.abs(), 1.0); // разворот на 180° — руль выкручен до упора
  });

  test('цель почти достигнута — газ и руль обнуляются', () {
    final input = computePoliceInput(
      position: vm.Vector3(0, 0, 0),
      heading: 0.5,
      targetPosition: vm.Vector3(0, 0, 0.05),
    );
    expect(input.throttle, 0.0);
    expect(input.steer, 0.0);
  });

  test('курс уже совпадает с направлением на цель под произвольным углом', () {
    const heading = math.pi / 4;
    final direction = vm.Vector3(math.sin(heading), 0, math.cos(heading));
    final input = computePoliceInput(
      position: vm.Vector3(0, 0, 0),
      heading: heading,
      targetPosition: direction * 10,
    );
    expect(input.steer, closeTo(0.0, 1e-9));
  });
}
