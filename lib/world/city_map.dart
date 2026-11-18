import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;
import 'package:vector_math/vector_math.dart' as vm;
import '../player/character_motion.dart' show CharacterRayHit;
import 'city_barrier.dart';
import 'city_surface.dart';
import 'facade_profile.dart';

class CityFixture {
  CityFixture.fromJson(Map<String, dynamic> json)
    : kind = json['kind'] as String,
      x = (json['point'][0] as num).toDouble(),
      z = (json['point'][1] as num).toDouble(),
      y = (json['y'] as num? ?? 0).toDouble(),
      yaw = (json['yaw'] as num? ?? 0).toDouble(),
      placement = json['placement'] as String,
      source = (json['osm'] ?? json['basis']) as String;
  final String kind, placement, source;
  final double x, y, z, yaw;
  vm.Vector3 get position => vm.Vector3(x, y, z);
  vm.Vector4 get groundLight {
    final p = lightPosition;
    return vm.Vector4(
      p.x,
      p.z,
      kind == 'porch_light' ? 4.5 : 10.5,
      kind == 'porch_light' ? 0.22 : 0.85,
    );
  }

  vm.Vector3 get lightPosition => kind == 'porch_light'
      ? vm.Vector3(x, y + 2.2, z)
      : vm.Vector3(x + math.sin(yaw) * .92, y + 5.5, z + math.cos(yaw) * .92);
  double distanceSquared(double px, double pz) =>
      (px - x) * (px - x) + (pz - z) * (pz - z);
}

class CityMap {
  CityMap(
    this.fixtures, {
    this.barriers = const [],
    this.surfaces = const [],
    this.facadeProfiles = const [],
    this.parking = const [],
  });
  factory CityMap.fromJson(Map<String, dynamic> json) => CityMap(
    [
      for (final raw in json['fixtures'] as List)
        CityFixture.fromJson(raw as Map<String, dynamic>),
    ],
    parking: [
      for (final p in json['parking'] as List? ?? const [])
        (
          position: vm.Vector3(
            (p['point'][0] as num).toDouble(),
            (p['y'] as num).toDouble(),
            (p['point'][1] as num).toDouble(),
          ),
          yaw: (p['yaw'] as num).toDouble(),
        ),
    ],
    facadeProfiles: [
      for (final b in json['startBlock']?['buildings'] as List? ?? const [])
        FacadeProfile.fromJson(b as Map<String, dynamic>),
    ],
    surfaces: [
      for (final p in json['startBlock']?['parcels'] as List? ?? const [])
        CitySurface([
          for (final v in p['outline'])
            vm.Vector2((v[0] as num).toDouble(), (v[1] as num).toDouble()),
        ]),
      for (final area in json['areas'] as List? ?? const [])
        CitySurface([
          for (final p in area['points'])
            vm.Vector2((p[0] as num).toDouble(), (p[1] as num).toDouble()),
        ]),
    ],
    barriers: [
      for (final fence in json['barriers'] as List? ?? const [])
        for (final section in fence['sections'] as List? ?? const [])
          CityBarrier(
            a: vm.Vector2(
              (section['a'][0] as num).toDouble(),
              (section['a'][1] as num).toDouble(),
            ),
            b: vm.Vector2(
              (section['b'][0] as num).toDouble(),
              (section['b'][1] as num).toDouble(),
            ),
            y: (section['y'] as num).toDouble(),
            height: (fence['height'] as num).toDouble(),
            thickness: (fence['thickness'] as num).toDouble(),
          ),
    ],
  );
  final List<CityFixture> fixtures;
  final List<CityBarrier> barriers;
  final List<CitySurface> surfaces;
  final List<FacadeProfile> facadeProfiles;
  final List<({vm.Vector3 position, double yaw})> parking;
  CharacterRayHit? castBarriers(
    vm.Vector3 origin,
    vm.Vector3 direction,
    double reach,
  ) {
    CharacterRayHit? nearest;
    for (final barrier in barriers) {
      final hit = barrier.cast(origin, direction, nearest?.distance ?? reach);
      if (hit != null) nearest = hit;
    }
    return nearest;
  }

  static Future<CityMap> load() async => CityMap.fromJson(
    jsonDecode(await rootBundle.loadString('assets/data/city_map.json'))
        as Map<String, dynamic>,
  );
  List<CityFixture> nearby(
    String kind,
    double x,
    double z, {
    double radius = 80,
    int limit = 8,
  }) {
    final found =
        fixtures
            .where(
              (f) =>
                  f.kind == kind && f.distanceSquared(x, z) <= radius * radius,
            )
            .toList()
          ..sort(
            (a, b) =>
                a.distanceSquared(x, z).compareTo(b.distanceSquared(x, z)),
          );
    return found.take(limit).toList();
  }

  bool treeClear(double x, double z, double radius) => !fixtures.any(
    (f) =>
        f.distanceSquared(x, z) <
        math.pow(radius + (f.kind == 'bench' ? 1.2 : .5), 2),
  );
}

/// A short rest is cancelled by walking away, damage, pursuit or entering a car.
/// Sitting animation is intentionally not implied by this gameplay timer.
class BenchRest {
  CityFixture? bench;
  double remaining = 0;
  vm.Vector3? _start;
  bool get active => bench != null;
  void start(CityFixture target, vm.Vector3 position) {
    bench = target;
    remaining = 5;
    _start = position.clone();
  }

  bool update(double dt, vm.Vector3 position, {required bool allowed}) {
    if (!active) return false;
    if (!allowed ||
        (position - _start!).length2 > .25 ||
        bench!.distanceSquared(position.x, position.z) > 9) {
      cancel();
      return false;
    }
    remaining = math.max(0, remaining - dt);
    if (remaining > 0) return false;
    cancel();
    return true;
  }

  void cancel() {
    bench = null;
    remaining = 0;
    _start = null;
  }
}
