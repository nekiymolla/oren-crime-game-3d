import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'package:crime_oren/world/city_map.dart';
import 'package:crime_oren/player/player_health.dart';

CityFixture bench(double x) => CityFixture.fromJson({
  'kind': 'bench',
  'point': [x, 0],
  'yaw': 0,
  'placement': 'inferred',
  'basis': 'way/1',
});
void main() {
  test('hit revision detects armour damage even after health regeneration', () {
    final health = PlayerHealth()..health = 40;
    final revision = health.damageRevision;
    health.update(2);
    health.addArmor(20);
    health.takeDamage(1);
    expect(health.health, greaterThan(40));
    expect(health.damageRevision, revision + 1);
    health.takeDamage(0);
    expect(health.damageRevision, revision + 1);
  });
  test(
    'nearby fixtures are ordered, limited and filtered by distance and kind',
    () {
      final map = CityMap([
        bench(8),
        bench(2),
        bench(-3),
        CityFixture.fromJson({
          'kind': 'lamp',
          'point': [0, 0],
          'placement': 'mapped',
          'osm': 'node/1',
        }),
      ]);
      expect(map.nearby('bench', 0, 0, radius: 4, limit: 1).single.x, 2);
      expect(map.nearby('bench', 0, 0, radius: 4).map((f) => f.x), [2, -3]);
    },
  );
  test('rest completes once after five seconds', () {
    final rest = BenchRest()..start(bench(0), vm.Vector3(0, 0, 1));
    expect(rest.update(4, vm.Vector3(0, 0, 1), allowed: true), false);
    expect(rest.update(1, vm.Vector3(0, 0, 1), allowed: true), true);
    expect(rest.active, false);
    expect(rest.update(1, vm.Vector3(0, 0, 1), allowed: true), false);
  });
  test('rest cancels on movement or unavailable gameplay state', () {
    final rest = BenchRest()..start(bench(0), vm.Vector3.zero());
    expect(rest.update(1, vm.Vector3(1, 0, 0), allowed: true), false);
    expect(rest.active, false);
    rest.start(bench(0), vm.Vector3.zero());
    expect(rest.update(5, vm.Vector3.zero(), allowed: false), false);
    expect(rest.active, false);
  });
  test('snapshot separates mapped geometry from approximate dressing', () {
    final data =
        jsonDecode(File('assets/data/city_map.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(data['paths'], hasLength(46));
    expect(data['areas'], hasLength(4));
    final map = CityMap.fromJson(data);
    expect(map.fixtures.where((f) => f.kind == 'lamp'), hasLength(81));
    expect(map.fixtures.where((f) => f.kind == 'bench'), hasLength(40));
    expect(map.fixtures.where((f) => f.kind == 'tree'), hasLength(100));
    for (final f in map.fixtures) {
      expect(f.x.isFinite && f.y.isFinite && f.z.isFinite, true);
      expect(f.source, startsWith(f.placement == 'mapped' ? 'node/' : 'way/'));
      if (f.kind != 'block') expect(f.placement, 'inferred');
    }
    expect(map.fixtures.where((f) => f.kind == 'fountain'), isEmpty);
    expect(data['barriers'], hasLength(11));
    expect(map.facadeProfiles, hasLength(8));
    expect(map.parking, hasLength(8));
    expect(map.barriers, isNotEmpty);
    for (final fence in data['barriers']) {
      expect(fence['placement'], 'inferred');
      expect(fence['basis'], startsWith('way/'));
      expect(fence['gate']['width'], greaterThanOrEqualTo(3.6));
    }
  });
}
