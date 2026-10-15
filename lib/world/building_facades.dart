import 'package:flutter_scene/scene.dart';

/// Фасады зданий района: материалы стен из osm2world (однотонная
/// штукатурка/бетон) заменяются шейдером building_facade.fmat — та же
/// текстура и цвет дома, плюс процедурные окна по этажам, ночью часть из
/// них горит. Отдельные плашки окон osm2world (материал Windows — были
/// лишь у немногих домов) прячутся, чтобы окна не двоились.
///
/// На каждый исходный материал стены — один фасадный (тот же draw call,
/// батчинг чанка не страдает). Шейдер грузится асинхронно: в первые
/// мгновения после загрузки чанка стены ещё старые — заметить нельзя,
/// чанки грузятся за пределами видимости.
class BuildingFacades {
  static const String shaderPath = 'assets/shaders/building_facade.fmat';

  /// Материалы стен osm2world, на которые ложатся окна.
  static const Set<String> wallMaterials = {'Plaster002', 'Concrete034'};

  final Map<PhysicallyBasedMaterial, Future<PreprocessedMaterial?>> _facades = {};
  final List<PreprocessedMaterial> _ready = [];
  double _night = 0.0;
  double _wetness = 0.0;
  bool _failed = false;

  /// Чанк района загружен — подменить стены.
  void registerChunk(Node chunk) {
    if (_failed) return;
    for (final meshNode in chunk.meshNodes) {
      _apply(meshNode);
    }
  }

  /// Меш узла заменяется копией с новыми материалами: движок держит готовые
  /// элементы отрисовки, и правка `primitive.material` у уже показанного
  /// меша до кадра не доходит — а присвоение нового меша их обновляет.
  Future<void> _apply(Node meshNode) async {
    final source = meshNode.mesh;
    if (source == null) return;
    final replacements = <int, Material>{};
    final hidden = <int>{};
    for (var i = 0; i < source.primitives.length; i++) {
      final material = source.primitives[i].material;
      if (material.name == 'Windows') {
        hidden.add(i);
      } else if (material is PhysicallyBasedMaterial && wallMaterials.contains(material.name)) {
        final facade = await _facades.putIfAbsent(material, () => _build(material));
        if (facade != null) replacements[i] = facade;
      }
    }
    if (replacements.isEmpty && hidden.isEmpty) return;
    // Пока грузился шейдер, чанк могли выгрузить или меш заменить.
    if (!identical(meshNode.mesh, source)) return;
    final mesh = source.clone();
    for (final entry in replacements.entries) {
      mesh.primitives[entry.key].material = entry.value;
    }
    for (final index in hidden) {
      mesh.primitives[index]
        ..visible = false
        ..castsShadow = false;
    }
    meshNode.mesh = mesh;
  }

  /// Ночь 0..1 (суточный цикл): горящие окна.
  set night(double value) {
    if ((value - _night).abs() < 0.005) return;
    _night = value;
    for (final facade in _ready) {
      facade.parameters.setFloat('night', value);
    }
  }

  /// Мокрые после дождя стены блестят.
  set wetness(double value) {
    if ((value - _wetness).abs() < 0.01) return;
    _wetness = value;
    for (final facade in _ready) {
      facade.parameters.setFloat('wetness', value);
    }
  }

  Future<PreprocessedMaterial?> _build(PhysicallyBasedMaterial wall) async {
    try {
      final facade = await loadFmatMaterial(shaderPath);
      final texture = wall.baseColorTexture;
      final gpuTexture = texture?.sampledTexture;
      if (gpuTexture != null) {
        facade.parameters.setTexture('wall_texture', gpuTexture, sampler: texture!.sampledSampler);
      }
      facade.parameters
        ..setVec4('tint', wall.baseColorFactor)
        ..setFloat('night', _night)
        ..setFloat('wetness', _wetness);
      _ready.add(facade);
      return facade;
    } catch (error) {
      // Без шейдера стены остаются как были.
      _failed = true;
      // ignore: avoid_print
      print('BuildingFacades: шейдер фасада не загрузился ($error)');
      return null;
    }
  }
}
