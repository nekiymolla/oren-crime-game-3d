import 'dart:math' as math;

import 'package:crime_oren/weapons/ballistics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  final feet = vm.Vector3(0, 0, 10);
  const radius = 0.3;
  const height = 1.5;

  test('луч в грудь попадает в переднюю стенку капсулы', () {
    final t = rayVerticalCapsule(vm.Vector3(0, 1.0, 0), vm.Vector3(0, 0, 1), 50, feet, radius, height);
    expect(t, closeTo(10 - radius, 1e-6));
  });

  test('мимо сбоку, поверх головы и дальше дальности — промах', () {
    expect(rayVerticalCapsule(vm.Vector3(0.5, 1.0, 0), vm.Vector3(0, 0, 1), 50, feet, radius, height), isNull);
    expect(rayVerticalCapsule(vm.Vector3(0, 1.6, 0), vm.Vector3(0, 0, 1), 50, feet, radius, height), isNull);
    expect(rayVerticalCapsule(vm.Vector3(0, 1.0, 0), vm.Vector3(0, 0, 1), 5, feet, radius, height), isNull);
  });

  test('макушка — полусфера: попадание сверху', () {
    final t = rayVerticalCapsule(vm.Vector3(0, 5, 10), vm.Vector3(0, -1, 0), 50, feet, radius, height);
    expect(t, closeTo(5 - height, 1e-6));
  });

  test('зоны тела по высоте попадания', () {
    expect(zoneForHitHeight(1.4, height), BodyZone.head);
    expect(zoneForHitHeight(1.0, height), BodyZone.torso);
    expect(zoneForHitHeight(0.4, height), BodyZone.legs);
  });

  test('разброс — всегда внутри конуса и не пустой', () {
    final random = math.Random(3);
    final forward = vm.Vector3(0.3, -0.1, 1).normalized();
    final halfAngle = 2.0 * math.pi / 180;
    var maxAngle = 0.0;
    for (var i = 0; i < 2000; i++) {
      final d = spreadDirection(forward, halfAngle, random);
      expect(d.length, closeTo(1.0, 1e-5)); // float32
      maxAngle = math.max(maxAngle, math.acos(d.dot(forward).clamp(-1.0, 1.0)));
    }
    expect(maxAngle, lessThanOrEqualTo(halfAngle + 1e-3));
    expect(maxAngle, greaterThan(halfAngle * 0.8));
  });

  test('автоприцел: ближайшая по углу цель, в пределах угла и дальности', () {
    final origin = vm.Vector3.zero();
    final aim = vm.Vector3(0, 0, 1);
    final points = [
      vm.Vector3(3, 0, 20), // ~8.5°
      vm.Vector3(1, 0, 20), // ~2.9°
      vm.Vector3(0, 0, 80), // 0°, но дальше дальности
    ];
    final pick = pickAimAssistTarget(origin, aim, points, maxAngleRadians: 10 * math.pi / 180, maxDistance: 50);
    expect(pick, 1);
    expect(
      pickAimAssistTarget(origin, aim, [points[0]], maxAngleRadians: 5 * math.pi / 180, maxDistance: 50),
      isNull,
    );
  });
}
