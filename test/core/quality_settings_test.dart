import 'dart:convert';

import 'package:crime_oren/core/quality_settings.dart';
import 'package:flutter_scene/scene.dart' show AntiAliasingMode;
import 'package:flutter_test/flutter_test.dart';

const _json = '''
{
  "defaultPreset": "high",
  "presets": {
    "high": {
      "renderScale": 1.0,
      "antiAliasing": "auto",
      "shadowsEnabled": true,
      "shadowCascadeCount": 4,
      "shadowMaxDistance": 150.0,
      "ambientOcclusionEnabled": true,
      "bloomEnabled": true,
      "drawDistanceMeters": 1000.0,
      "pedestrianPopulation": 16,
      "maxTrees": 220
    },
    "low": {
      "renderScale": 0.5,
      "antiAliasing": "none",
      "shadowsEnabled": false,
      "shadowCascadeCount": 2,
      "shadowMaxDistance": 80.0,
      "ambientOcclusionEnabled": false,
      "bloomEnabled": false,
      "drawDistanceMeters": 350.0,
      "pedestrianPopulation": 8,
      "maxTrees": 80
    }
  }
}
''';

void main() {
  QualityPresets parse() =>
      QualityPresets.fromJson(jsonDecode(_json) as Map<String, dynamic>);

  test('QualitySettings.fromJson разбирает все поля пресета', () {
    final low = parse().presets['low']!;

    expect(low.name, 'low');
    expect(low.renderScale, 0.5);
    expect(low.antiAliasing, AntiAliasingMode.none);
    expect(low.shadowsEnabled, isFalse);
    expect(low.shadowCascadeCount, 2);
    expect(low.shadowMaxDistance, 80.0);
    expect(low.ambientOcclusionEnabled, isFalse);
    expect(low.bloomEnabled, isFalse);
    expect(low.drawDistanceMeters, 350.0);
    expect(low.pedestrianPopulation, 8);
    expect(low.maxTrees, 80);
  });

  test('defaultPreset берётся по имени из JSON', () {
    expect(parse().defaultPreset.name, 'high');
  });

  test('shadowMapResolution необязателен и падает в дефолт движка 1024', () {
    // В _json этого поля нет ни у одного пресета — старые конфиги должны
    // читаться без правок.
    expect(parse().presets['low']!.shadowMapResolution, 1024);
  });

  test('ordered идёт от дешёвого к дорогому и пропускает отсутствующие', () {
    // В этом JSON нет medium — порядок не должен ломаться из-за дыры.
    expect(parse().ordered.map((preset) => preset.name), ['low', 'high']);
  });

  test('неизвестное имя anti-aliasing не роняет парсинг, а падает в auto', () {
    final json = jsonDecode(_json) as Map<String, dynamic>;
    final presets = json['presets'] as Map<String, dynamic>;
    (presets['low'] as Map<String, dynamic>)['antiAliasing'] = 'нет такого';

    expect(QualityPresets.fromJson(json).presets['low']!.antiAliasing, AntiAliasingMode.auto);
  });
}
