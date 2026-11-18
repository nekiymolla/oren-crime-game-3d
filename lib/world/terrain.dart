import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'terrain_height.dart';
import 'streaming_work.dart';

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
  final material = UnlitMaterial()
    ..baseColorFactor = vm.Vector4(0.42, 0.55, 0.28, 1.0);
  return Node(mesh: Mesh(geometry, material));
}

/// Земля с текстурами травы и тенями (assets/shaders/ground.fmat) — для
/// пресетов, где плоскость во весь экран не съест кадр (quality.json,
/// texturedGround). Текстуры лежат в assets/models/ground/ground_textures.glb
/// (tools/assets/prepare_ground.mjs). null — не загрузилось, тогда остаётся
/// однотонная заливка [buildPlaceholderGround].
class TexturedGround {
  TexturedGround._(this.node, this._material, this.height);

  final Node node;
  final Material _material;
  final TerrainHeight height;
  final Map<(int, int), Node> _tiles = {};
  final _center = StreamingCenter(cellSize: 200);
  final _cached = <(int, int), Node>{};
  static final _indices = _buildIndices();

  static List<int> _buildIndices() {
    final result = <int>[];
    for (var z = 0; z < 50; z++) {
      for (var x = 0; x < 50; x++) {
        final a = z * 51 + x, b = a + 1, c = a + 51, d = c + 1;
        result.addAll([a, c, b, b, c, d]);
      }
    }
    return result;
  }

  void updateAround(vm.Vector3 position) {
    if (!_center.update(position.x, position.z)) return;
    final (cx, cz) = _center.cell;
    final wanted = <(int, int)>{
      for (var z = cz - 1; z <= cz + 1; z++)
        for (var x = cx - 1; x <= cx + 1; x++) (x, z),
    };
    for (final key in _tiles.keys.toList()) {
      if (!wanted.contains(key)) {
        final tile = _tiles.remove(key)!;
        node.remove(tile);
        _cached[key] = tile;
      }
    }
    for (final key in wanted) {
      if (_tiles.containsKey(key)) continue;
      final cached = _cached.remove(key);
      if (cached != null) {
        _tiles[key] = cached;
        node.add(cached);
        continue;
      }
      final positions = Float32List(51 * 51 * 3),
          normals = Float32List(51 * 51 * 3);
      for (var z = 0; z <= 50; z++) {
        for (var x = 0; x <= 50; x++) {
          final wx = key.$1 * 200.0 + x * 4, wz = key.$2 * 200.0 + z * 4;
          final i = (z * 51 + x) * 3;
          positions[i] = wx;
          positions[i + 1] = height.heightAt(wx, wz) - 0.035;
          positions[i + 2] = wz;
          const e = .1;
          final nx = height.heightAt(wx - e, wz) - height.heightAt(wx + e, wz);
          final nz = height.heightAt(wx, wz - e) - height.heightAt(wx, wz + e);
          final inverseLength = 1 / math.sqrt(nx * nx + 4 * e * e + nz * nz);
          normals[i] = nx * inverseLength;
          normals[i + 1] = 2 * e * inverseLength;
          normals[i + 2] = nz * inverseLength;
        }
      }
      final tile = Node(
        mesh: Mesh(
          MeshGeometry.fromArrays(
            positions: positions,
            normals: normals,
            indices: _indices,
            retainCpuData: false,
          ),
          _material,
        ),
      );
      // Ground receives shadows, but does not need to cast them.
      tile.mesh!.primitives.first.castsShadow = false;
      _tiles[key] = tile;
      node.add(tile);
    }
    while (_cached.length > 16) {
      _cached.remove(_cached.keys.first);
    }
  }

  static Future<TexturedGround?> load({
    required double sizeMeters,
    required TerrainHeight height,
    bool textured = true,
  }) async {
    TexturedGround create(Material material) {
      final node = Node();
      final fallback = Node(
        mesh: Mesh(
          PlaneGeometry(width: sizeMeters, depth: sizeMeters),
          material,
        ),
      )..position = vm.Vector3(0, -0.06, 0);
      fallback.mesh!.primitives.first.castsShadow = false;
      node.add(fallback);
      return TexturedGround._(node, material, height);
    }

    TexturedGround plain() => create(
      UnlitMaterial()..baseColorFactor = vm.Vector4(0.42, 0.48, 0.30, 1),
    );
    if (!textured) return plain();
    try {
      final textures = await loadScene(
        'assets/models/ground/ground_textures.glb',
      );
      final material = await loadFmatMaterial('assets/shaders/ground.fmat');
      for (final (name, parameter) in [
        ('Grass', 'grass_texture'),
        ('Dirt', 'dirt_texture'),
      ]) {
        final source = textures
            .getChildByName(name)
            ?.mesh
            ?.primitives
            .first
            .material;
        final texture = source is PhysicallyBasedMaterial
            ? source.baseColorTexture
            : null;
        final gpuTexture = texture?.sampledTexture;
        if (gpuTexture == null) return plain();
        material.parameters.setTexture(
          parameter,
          gpuTexture,
          sampler: texture!.sampledSampler,
        );
      }
      return create(material);
    } catch (error) {
      // ignore: avoid_print
      print('TexturedGround: не загрузилась ($error) — однотонная земля');
      return plain();
    }
  }

  void updateStreetLights(List<vm.Vector4> positions, double night) {
    if (_material is! PreprocessedMaterial) return;
    final params = _material.parameters;
    for (var i = 0; i < 8; i++) {
      final p = i < positions.length ? positions[i] : null;
      params.setVec4(
        'street_lamp_$i',
        vm.Vector4(
          p?.x ?? 0,
          p?.y ?? 0,
          p?.z ?? 1,
          p == null ? 0 : night * p.w,
        ),
      );
    }
  }

  /// Оттенок неба (SkyLighting.unlitTint) и снег 0..1 — каждый кадр из
  /// суточного цикла.
  void update(vm.Vector3 tint, double snowCover) {
    final material = _material;
    if (material is UnlitMaterial) {
      material.baseColorFactor = vm.Vector4(
        0.42 * tint.x,
        0.48 * tint.y,
        0.30 * tint.z,
        1,
      );
      return;
    }
    (material as PreprocessedMaterial).parameters
      ..setVec3('light_tint', tint)
      ..setFloat('snow', snowCover);
  }
}
