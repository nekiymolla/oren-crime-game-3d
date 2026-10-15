import 'dart:math' as math;

import 'package:crime_oren/police/police_car.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  chaseDrivingTests();

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

void chaseDrivingTests() {
  test('перед крутым поворотом тормозит, перед пологим — нет', () {
    expect(cornerThrottle(baseThrottle: 1, speed: 13, distanceToWaypoint: 10, turnAngle: math.pi / 2), -1.0);
    expect(cornerThrottle(baseThrottle: 1, speed: 13, distanceToWaypoint: 10, turnAngle: 0.2), 1.0);
    // Далеко от поворота — ещё не тормозит, медленно — можно газовать.
    expect(cornerThrottle(baseThrottle: 1, speed: 13, distanceToWaypoint: 40, turnAngle: math.pi / 2), 1.0);
    expect(cornerThrottle(baseThrottle: 1, speed: 3, distanceToWaypoint: 10, turnAngle: math.pi / 2), 1.0);
  });

  test('упёрлась — через паузу сдаёт назад, потом снова вперёд', () {
    final stuck = StuckRecovery();
    var reversed = false;
    for (var i = 0; i < 100; i++) {
      if (stuck.update(1 / 60, speed: 0.0, wantsToMove: true)) {
        reversed = true;
        break;
      }
    }
    expect(reversed, isTrue);
    expect(stuck.isReversing, isTrue);
    for (var i = 0; i < 100; i++) {
      stuck.update(1 / 60, speed: 2.0, wantsToMove: true);
    }
    expect(stuck.isReversing, isFalse);
    // Едет нормально — не сдаёт.
    expect(stuck.update(5, speed: 10, wantsToMove: true), isFalse);
  });

  test('машина прямо по курсу — объезд, сбоку или сзади — нет', () {
    final me = vm.Vector3.zero();
    expect(isBlockedAhead(me, 0, [vm.Vector3(0.5, 0, 8)]), isTrue);
    expect(isBlockedAhead(me, 0, [vm.Vector3(4, 0, 8)]), isFalse); // соседняя полоса
    expect(isBlockedAhead(me, 0, [vm.Vector3(0, 0, -6)]), isFalse); // сзади
    expect(isBlockedAhead(me, math.pi / 2, [vm.Vector3(8, 0, 0)]), isTrue); // курс на +X
  });

  test('объезд — влево от курса, зеркально rightOf трафика', () {
    final target = overtakeTarget(vm.Vector3.zero(), vm.Vector3(0, 0, 20));
    // Курс +Z; rightOf(+Z) = (-1,0,0) у трафика, значит лево — +X.
    expect(target.x, closeTo(3.5, 1e-6));
    expect(target.z, closeTo(20, 1e-6));
  });
}
