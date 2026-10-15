import 'package:crime_oren/weather/wet_roads_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('сухой асфальт выглядит как из пайплайна, отражений нет', () {
    final dry = WetSurfaceLook.at(0.0);
    expect(dry.roughness, WetRoadsView.marker);
    expect(dry.albedo, 1.0);
    expect(dry.reflections, 0.0);
  });

  test('мокрый — темнее и достаточно гладкий для SSR движка', () {
    final wet = WetSurfaceLook.at(1.0);
    // SSR в flutter_scene_ssr.frag на полную только ниже roughness 0.25.
    expect(wet.roughness, lessThan(0.25));
    expect(wet.albedo, lessThan(0.7));
    expect(wet.reflections, 1.0);
  });

  test('отражения нарастают плавно и не раньше порога', () {
    expect(WetSurfaceLook.at(WetSurfaceLook.minReflectiveWetness).reflections, 0.0);
    var previous = 0.0;
    for (var w = 0.1; w <= 1.0; w += 0.05) {
      final r = WetSurfaceLook.at(w).reflections;
      expect(r, greaterThanOrEqualTo(previous));
      expect(r - previous, lessThan(0.25), reason: 'скачок на w=$w');
      previous = r;
    }
  });

  test('метка пайплайна узнаётся с допуском float32, обычные материалы — нет', () {
    expect(WetRoadsView.isMarked(0.987), isTrue);
    expect(WetRoadsView.isMarked(0.98699998856), isTrue);
    expect(WetRoadsView.isMarked(1.0), isFalse);
    expect(WetRoadsView.isMarked(0.5), isFalse);
  });
}
