import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Как выглядит мокрый асфальт при данной мокроте (0..1). Чистые числа —
/// проверены тестами; в объекты движка их переносит [WetRoadsView].
class WetSurfaceLook {
  const WetSurfaceLook({required this.roughness, required this.albedo, required this.reflections});

  /// Мокрота 0..1 (WeatherParams.wetness).
  factory WetSurfaceLook.at(double wetness) {
    final w = wetness.clamp(0.0, 1.0);
    // Отражения появляются не сразу: пока асфальт только темнеет, гладким
    // он ещё не стал. Плавно, чтобы не было скачка на пороге.
    final t = ((w - minReflectiveWetness) / 0.5).clamp(0.0, 1.0);
    return WetSurfaceLook(
      roughness: WetRoadsView.marker + (_wetRoughness - WetRoadsView.marker) * w,
      albedo: 1.0 + (_wetAlbedo - 1.0) * w,
      reflections: t * t * (3 - 2 * t),
    );
  }

  /// Ниже этой мокроты экранные отражения не включаются вовсе (проход не
  /// стоит ничего, пока асфальт сухой).
  static const double minReflectiveWetness = 0.1;

  /// Шероховатость мокрого асфальта. SSR движка гаснет на roughnessFactor
  /// от 0.25 до 0.55 (flutter_scene_ssr.frag) — мокрый должен быть ниже.
  static const double _wetRoughness = 0.12;

  /// Мокрое темнее сухого: вода убирает рассеяние в верхнем слое.
  static const double _wetAlbedo = 0.55;

  /// roughnessFactor материала (умножается на metallicRoughness-текстуру).
  final double roughness;

  /// Множитель baseColor.
  final double albedo;

  /// Сила экранных отражений 0..1.
  final double reflections;
}

/// Мокрые дороги и тротуары в дождь: материалы асфальта становятся темнее
/// и гладкими, а экранные отражения (SSR) рисуют в них неон, фары и окна.
/// SSR в движке сам пропускает шероховатые поверхности, так что отражения
/// появляются только на мокром асфальте, а не на стенах домов.
class WetRoadsView {
  WetRoadsView({required this.scene, required this.reflectionsAllowed});

  /// roughnessFactor, которым пайплайн помечает мокнущие материалы
  /// (tools/osm_pipeline/mark_night_materials.mjs): движок не хранит имена
  /// материалов glTF, а 0.987 вместо 1 на глаз неотличимо.
  static const double marker = 0.987;

  static bool isMarked(double roughnessFactor) => (roughnessFactor - marker).abs() < 1e-3;

  final Scene scene;

  /// SSR разрешены пресетом качества — дорогой экранный проход.
  final bool Function() reflectionsAllowed;

  final List<_ChunkSurfaces> _chunks = [];
  double _appliedWetness = -1.0;

  /// Чанк района загружен — запоминаем его мокнущие материалы и сразу
  /// приводим их к текущей мокроте.
  void registerChunk(Node chunk) {
    final materials = <PhysicallyBasedMaterial>{};
    for (final meshNode in chunk.meshNodes) {
      for (final primitive in meshNode.mesh!.primitives) {
        final material = primitive.material;
        if (material is PhysicallyBasedMaterial && isMarked(material.roughnessFactor)) materials.add(material);
      }
    }
    if (materials.isEmpty) return;
    final surfaces = _ChunkSurfaces(chunk, [
      for (final material in materials) (material: material, dryColor: material.baseColorFactor.clone()),
    ]);
    _chunks.add(surfaces);
    if (_appliedWetness > 0) surfaces.apply(WetSurfaceLook.at(_appliedWetness));
  }

  void update(double wetness) {
    // Выгруженные чанки (стример снял их со сцены) больше не держим.
    _chunks.removeWhere((surfaces) => surfaces.chunk.parent == null);

    if ((wetness - _appliedWetness).abs() > 0.005) {
      _appliedWetness = wetness;
      final look = WetSurfaceLook.at(wetness);
      for (final surfaces in _chunks) {
        surfaces.apply(look);
      }
    }

    // Пишется каждый кадр: смена пресета качества пересобирает
    // EnvironmentSettings целиком, и тот выключает SSR.
    final look = WetSurfaceLook.at(_appliedWetness);
    final enabled = reflectionsAllowed() && look.reflections > 0.0;
    final ssr = scene.screenSpaceReflections..enabled = enabled;
    if (!enabled) return;
    ssr
      ..intensity = look.reflections
      // Неон на фасадах через улицу — дальше дефолтных 24 м.
      ..maxDistance = 40.0
      ..stride = 6.0
      ..maxSteps = 64
      ..blur = 0.35
      ..distanceFadeStart = 0.5
      // Главный рычаг цены: отражения на мокром асфальте и так размыты.
      ..resolutionScale = 0.5;
  }
}

class _ChunkSurfaces {
  _ChunkSurfaces(this.chunk, this.materials);

  final Node chunk;
  final List<({PhysicallyBasedMaterial material, vm.Vector4 dryColor})> materials;

  void apply(WetSurfaceLook look) {
    for (final (:material, :dryColor) in materials) {
      material
        ..roughnessFactor = look.roughness
        ..baseColorFactor = vm.Vector4(
          dryColor.x * look.albedo,
          dryColor.y * look.albedo,
          dryColor.z * look.albedo,
          dryColor.w,
        );
    }
  }
}
