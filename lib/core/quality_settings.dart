import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart';

/// Уровень качества из assets/data/quality.json (ТЗ, раздел 23). Числа живут
/// в JSON, а не в коде, чтобы подбирать их на устройстве правкой ассета —
/// подбор всё равно идёт замерами, а не рассуждениями.
///
/// Поля делятся на две группы по тому, когда применяются:
/// - рендерные (renderScale, AA, тени, AO/bloom, дальность) — [applyToScene]
///   меняет их на живой сцене, что и позволяет снимать A/B-замеры без
///   пересборки;
/// - мировые ([pedestrianPopulation], [maxTrees]) — читаются один раз при
///   Game.load(), потому что меняют состав уже созданных систем.
class QualitySettings {
  const QualitySettings({
    required this.name,
    required this.renderScale,
    required this.antiAliasing,
    required this.shadowsEnabled,
    required this.shadowCascadeCount,
    required this.shadowMaxDistance,
    required this.shadowMapResolution,
    required this.ambientOcclusionEnabled,
    required this.bloomEnabled,
    required this.drawDistanceMeters,
    required this.pedestrianPopulation,
    required this.maxTrees,
  });

  factory QualitySettings.fromJson(String name, Map<String, dynamic> json) => QualitySettings(
    name: name,
    renderScale: (json['renderScale'] as num).toDouble(),
    antiAliasing: _parseAntiAliasing(json['antiAliasing'] as String),
    shadowsEnabled: json['shadowsEnabled'] as bool,
    shadowCascadeCount: json['shadowCascadeCount'] as int,
    shadowMaxDistance: (json['shadowMaxDistance'] as num).toDouble(),
    // Необязательное: старые конфиги без этого поля читаются как 1024 —
    // дефолт самого движка.
    shadowMapResolution: json['shadowMapResolution'] as int? ?? 1024,
    ambientOcclusionEnabled: json['ambientOcclusionEnabled'] as bool,
    bloomEnabled: json['bloomEnabled'] as bool,
    drawDistanceMeters: (json['drawDistanceMeters'] as num).toDouble(),
    pedestrianPopulation: json['pedestrianPopulation'] as int,
    maxTrees: json['maxTrees'] as int,
  );

  final String name;
  final double renderScale;
  final AntiAliasingMode antiAliasing;
  final bool shadowsEnabled;
  final int shadowCascadeCount;
  final double shadowMaxDistance;

  /// Сторона карты теней. Прямой fill-фактор shadow pass: 1024 -> 512 это
  /// вчетверо меньше пикселей, которые шедоу-проход обязан залить. Каскады
  /// и дальность теней на замере не дали ничего, а вот это не проверялось.
  final int shadowMapResolution;
  final bool ambientOcclusionEnabled;
  final bool bloomEnabled;

  /// Дальняя плоскость отсечения камеры, метры. Геометрии дальше загруженных
  /// чанков всё равно нет (радиус 1 = 600x600 м вокруг игрока), так что
  /// уменьшение обрезает в основном плейсхолдер-землю — но заодно сужает
  /// frustum и улучшает точность буфера глубины.
  final double drawDistanceMeters;

  final int pedestrianPopulation;
  final int maxTrees;

  /// Для debug-панели: снять один фактор, не трогая остальные. Пресеты
  /// отличаются сразу многим, а чтобы понять, что именно стоит дорого,
  /// нужно менять по одному (см. PROGRESS.md — на угадывании уже теряли
  /// раунд).
  QualitySettings copyWith({
    String? name,
    bool? shadowsEnabled,
    bool? ambientOcclusionEnabled,
    bool? bloomEnabled,
    int? shadowMapResolution,
  }) => QualitySettings(
    name: name ?? this.name,
    renderScale: renderScale,
    antiAliasing: antiAliasing,
    shadowsEnabled: shadowsEnabled ?? this.shadowsEnabled,
    shadowCascadeCount: shadowCascadeCount,
    shadowMaxDistance: shadowMaxDistance,
    shadowMapResolution: shadowMapResolution ?? this.shadowMapResolution,
    ambientOcclusionEnabled: ambientOcclusionEnabled ?? this.ambientOcclusionEnabled,
    bloomEnabled: bloomEnabled ?? this.bloomEnabled,
    drawDistanceMeters: drawDistanceMeters,
    pedestrianPopulation: pedestrianPopulation,
    maxTrees: maxTrees,
  );

  static AntiAliasingMode _parseAntiAliasing(String raw) => switch (raw) {
    'none' => AntiAliasingMode.none,
    'fxaa' => AntiAliasingMode.fxaa,
    'smaa' => AntiAliasingMode.smaa,
    'msaa' => AntiAliasingMode.msaa,
    _ => AntiAliasingMode.auto,
  };
}

/// Все пресеты сразу — переключатель в debug-меню перебирает их по кругу,
/// поэтому держим набор целиком, а не один выбранный.
class QualityPresets {
  const QualityPresets({required this.presets, required this.defaultName});

  factory QualityPresets.fromJson(Map<String, dynamic> json) {
    final raw = json['presets'] as Map<String, dynamic>;
    return QualityPresets(
      presets: {
        for (final entry in raw.entries)
          entry.key: QualitySettings.fromJson(entry.key, entry.value as Map<String, dynamic>),
      },
      defaultName: json['defaultPreset'] as String,
    );
  }

  final Map<String, QualitySettings> presets;
  final String defaultName;

  /// Порядок для перебора кнопкой — от самого дешёвого к самому дорогому,
  /// а не как легло в JSON.
  static const List<String> order = ['low', 'medium', 'high'];

  List<QualitySettings> get ordered => [
    for (final name in order)
      if (presets[name] != null) presets[name]!,
  ];

  QualitySettings get defaultPreset => presets[defaultName] ?? ordered.last;
}

Future<QualityPresets> loadQualityPresets() async {
  final raw = await rootBundle.loadString('assets/data/quality.json');
  return QualityPresets.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
