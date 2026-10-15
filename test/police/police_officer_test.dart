import 'dart:math';

import 'package:crime_oren/police/police_officer.dart';
import 'package:crime_oren/weapons/ballistics.dart';
import 'package:crime_oren/weapons/player_shooting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

class _Fake implements ShootTargets {
  _Fake(this.z, this.aimX);

  final double z;
  final double aimX;
  final List<int> shot = [];

  @override
  ({int index, double distance, BodyZone zone})? raycastShootable(vm.Vector3 origin, vm.Vector3 direction, double maxDistance) {
    final t = (z - origin.z) / direction.z;
    return t > 0 && t < maxDistance ? (index: 3, distance: t, zone: BodyZone.torso) : null;
  }

  @override
  bool applyShot(int index, double damage, vm.Vector3 from) {
    shot.add(index);
    return false;
  }

  @override
  void collectAimPoints(List<vm.Vector3> points, List<int> indices) {
    points.add(vm.Vector3(aimX, 1, z));
    indices.add(7);
  }

  @override
  int scareAround(vm.Vector3 shooter, double radius) => 2;
}

void main() {
  detourTests();

  test('при видимости сближается до дистанции остановки и не ближе', () {
    final officer = PoliceOfficer(position: vm.Vector3(0, 0, 0), unitId: 0);
    final target = vm.Vector3(0, 0, 30);
    for (var i = 0; i < 600; i++) {
      stepOfficer(officer, target, 1 / 60, hasLineOfSight: true, random: Random(i));
    }
    expect(30 - officer.position.z, closeTo(OfficerTuning.stopDistance, 1e-3));
    expect(officer.yaw, closeTo(0, 1e-6));
  });

  test('без видимости стоит и копит время без игрока, не стреляет', () {
    final officer = PoliceOfficer(position: vm.Vector3(0, 0, 0), unitId: 0)..fireCooldown = 0;
    final fired = stepOfficer(officer, vm.Vector3(0, 0, 20), 1.0, hasLineOfSight: false, random: Random(0));
    expect(fired, isFalse);
    expect(officer.position, vm.Vector3.zero());
    expect(officer.secondsWithoutSight, 1.0);
    stepOfficer(officer, vm.Vector3(0, 0, 20), 0.1, hasLineOfSight: true, random: Random(0));
    expect(officer.secondsWithoutSight, 0.0);
  });

  test('стреляет с паузами: за 10 секунд — около 10/fireInterval выстрелов', () {
    final officer = PoliceOfficer(position: vm.Vector3(0, 0, 0), unitId: 0);
    var shots = 0;
    for (var i = 0; i < 600; i++) {
      if (stepOfficer(officer, vm.Vector3(0, 0, 9), 1 / 60, hasLineOfSight: true, random: Random(i))) shots++;
    }
    final expected = 10 / OfficerTuning.fireInterval;
    expect(shots, inInclusiveRange((expected * 0.7).floor(), (expected * 1.3).ceil()));
  });

  test('вне дальности не стреляет; мёртвый не двигается', () {
    final far = PoliceOfficer(position: vm.Vector3(0, 0, 0), unitId: 0)..fireCooldown = 0;
    expect(stepOfficer(far, vm.Vector3(0, 0, 200), 0.01, hasLineOfSight: true, random: Random(0)), isFalse);

    final dead = PoliceOfficer(position: vm.Vector3(0, 0, 0), unitId: 0);
    expect(dead.takeDamage(150, vm.Vector3(0, 0, -5)), isTrue);
    expect(stepOfficer(dead, vm.Vector3(0, 0, 20), 1, hasLineOfSight: true, random: Random(0)), isFalse);
    expect(dead.position, vm.Vector3.zero());
  });

  test('шанс попадания падает с дистанцией и скоростью цели', () {
    final near = officerHitChance(5, targetSpeed: 0, targetInVehicle: false);
    final far = officerHitChance(35, targetSpeed: 0, targetInVehicle: false);
    final running = officerHitChance(5, targetSpeed: 4, targetInVehicle: false);
    final driving = officerHitChance(5, targetSpeed: 15, targetInVehicle: true);
    expect(near, greaterThan(far));
    expect(running, lessThan(near));
    expect(driving, lessThan(running));
    expect(far, greaterThan(0));
  });

  test('объединённые цели: ближайшая из наборов, индексы не путаются', () {
    final near = _Fake(10, 0.3);
    final far = _Fake(20, 0.0);
    final combined = CombinedShootTargets([far, near]);
    final hit = combined.raycastShootable(vm.Vector3.zero(), vm.Vector3(0, 0, 1), 100)!;
    expect(hit.distance, 10);
    combined.applyShot(hit.index, 10, vm.Vector3.zero());
    expect(near.shot, [3]);
    expect(far.shot, isEmpty);

    final points = <vm.Vector3>[];
    final indices = <int>[];
    combined.collectAimPoints(points, indices);
    expect(points.length, 2);
    combined.applyShot(indices[0], 10, vm.Vector3.zero());
    expect(far.shot, [7]);
    expect(combined.scareAround(vm.Vector3.zero(), 40), 4);
  });
}

void detourTests() {
  test('без видимости обходит преграду: прямо закрыто — идёт под углом', () {
    final officer = PoliceOfficer(position: vm.Vector3(0, 0, 0), unitId: 0);
    // Стена прямо по курсу на +Z; диагонали свободны.
    bool clear(vm.Vector3 from, vm.Vector3 direction, double distance) => direction.x.abs() > 0.3;
    stepOfficer(officer, vm.Vector3(0, 0, 30), 1.0, hasLineOfSight: false, random: Random(0), pathClear: clear);
    expect(officer.position.z, greaterThan(0)); // всё равно ближе к игроку
    expect(officer.position.x.abs(), greaterThan(0.5)); // но в обход
  });

  test('без видимости и без свободного пути стоит на месте', () {
    final officer = PoliceOfficer(position: vm.Vector3(0, 0, 0), unitId: 0);
    stepOfficer(officer, vm.Vector3(0, 0, 30), 1.0, hasLineOfSight: false, random: Random(0), pathClear: (_, _, _) => false);
    expect(officer.position, vm.Vector3.zero());
  });
}
