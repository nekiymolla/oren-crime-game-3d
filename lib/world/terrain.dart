import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Плоский участок земли — подложка везде, где OSM не размечает
/// поверхность (см. district_streamer.dart и filter_oversized_ways.py: даже
/// с landuse/natural большая часть реального района всё равно ничем не
/// покрыта). Цвет — под траву, а не нейтральный бетонный серый: прошлый
/// (0.16, 0.18, 0.16) визуально читался как серый — R≈G≈B слишком близко.
/// **Материал намеренно Unlit, а не PBR.** Замер на RMX5303 (19.09.2026):
/// эта плоскость одна съедала 92.6 мс raster из 149.7 — 62% всего кадра.
/// Геометрии в ней два треугольника, но она закрывает пол-экрана, и каждый
/// её пиксель считал физически корректное освещение с image-based lighting
/// из environment map — ради плоской зелёной заливки, которая вообще-то
/// временная подложка. Unlit просто заливает цветом, без освещения.
///
/// Цена: на подложку не падают тени и её не трогает солнце, поэтому цвет
/// подобран под то, как PBR-версия выглядела уже освещённой — иначе она
/// читается заметно темнее окружающей геометрии района.
///
/// Если когда-нибудь тут появится настоящий рельеф с материалами, считать
/// эти 92 мс заново: стоимость даёт не размер в метрах, а площадь на экране
/// помноженная на цену шейдера за пиксель.
Node buildPlaceholderGround({required double sizeMeters}) {
  final geometry = PlaneGeometry(width: sizeMeters, depth: sizeMeters);
  final material = UnlitMaterial()..baseColorFactor = vm.Vector4(0.42, 0.55, 0.28, 1.0);
  return Node(mesh: Mesh(geometry, material));
}

/// Земля с текстурами травы и тенями (assets/shaders/ground.fmat) — для
/// пресетов, где плоскость во весь экран не съест кадр (quality.json,
/// texturedGround). Текстуры лежат в assets/models/ground/ground_textures.glb
/// (tools/assets/prepare_ground.mjs). null — не загрузилось, тогда остаётся
/// однотонная заливка [buildPlaceholderGround].
class TexturedGround {
  TexturedGround._(this.node, this._material);

  final Node node;
  final PreprocessedMaterial _material;

  static Future<TexturedGround?> load({required double sizeMeters}) async {
    try {
      final textures = await loadScene('assets/models/ground/ground_textures.glb');
      final material = await loadFmatMaterial('assets/shaders/ground.fmat');
      for (final (name, parameter) in [('Grass', 'grass_texture'), ('Dirt', 'dirt_texture')]) {
        final source = textures.getChildByName(name)?.mesh?.primitives.first.material;
        final texture = source is PhysicallyBasedMaterial ? source.baseColorTexture : null;
        final gpuTexture = texture?.sampledTexture;
        if (gpuTexture == null) return null;
        material.parameters.setTexture(parameter, gpuTexture, sampler: texture!.sampledSampler);
      }
      final node = Node(mesh: Mesh(PlaneGeometry(width: sizeMeters, depth: sizeMeters), material));
      return TexturedGround._(node, material);
    } catch (error) {
      // ignore: avoid_print
      print('TexturedGround: не загрузилась ($error) — однотонная земля');
      return null;
    }
  }

  /// Оттенок неба (SkyLighting.unlitTint) и снег 0..1 — каждый кадр из
  /// суточного цикла.
  void update(vm.Vector3 tint, double snowCover) {
    _material.parameters
      ..setVec3('light_tint', tint)
      ..setFloat('snow', snowCover);
  }
}
