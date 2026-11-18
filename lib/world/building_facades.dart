import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter/scheduler.dart';
import 'streaming_work.dart';
import 'facade_profile.dart';
import 'streaming_diagnostics.dart';
import 'package:vector_math/vector_math.dart' as vm;

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

  final Map<Node, List<PreprocessedMaterial>> _chunks = {};
  final List<PreprocessedMaterial> _ready = [];
  double _night = 0.0;
  double _wetness = 0.0;
  bool _failed = false;
  List<FacadeProfile> profiles = const [];

  /// Чанк района загружен — подменить стены.
  Future<void> registerChunk(Node chunk) async {
    if (_failed) return;
    _chunks[chunk] = [];
    final walls = chunk.meshNodes
        .where(
          (node) => node.mesh!.primitives.any(
            (p) =>
                p.material.name == 'Windows' ||
                wallMaterials.contains(p.material.name),
          ),
        )
        .toList();
    await StreamingDiagnostics.async(
      chunk.name,
      'facade-preparation',
      () =>
          FramePreparation(
            yieldToFrame: () => SchedulerBinding.instance.endOfFrame,
          ).run(
            walls,
            (node) => _apply(node, chunk),
            isCurrent: () => _chunks.containsKey(chunk),
          ),
    );
  }

  /// Меш узла заменяется копией с новыми материалами: движок держит готовые
  /// элементы отрисовки, и правка `primitive.material` у уже показанного
  /// меша до кадра не доходит — а присвоение нового меша их обновляет.
  Future<void> _apply(Node meshNode, Node chunk) async {
    final source = meshNode.mesh;
    if (source == null) return;
    final replacements = <int, Material>{};
    final hidden = <int>{};
    for (var i = 0; i < source.primitives.length; i++) {
      final material = source.primitives[i].material;
      if (material.name == 'Windows') {
        hidden.add(i);
      } else if (material is PhysicallyBasedMaterial &&
          wallMaterials.contains(material.name)) {
        final facade = await StreamingDiagnostics.async(
          chunk.name,
          'facade-material',
          () => _build(material, meshNode, chunk),
        );
        if (facade != null) replacements[i] = facade;
      }
    }
    if (replacements.isEmpty && hidden.isEmpty) return;
    // Пока грузился шейдер, чанк могли выгрузить или меш заменить.
    if (!_chunks.containsKey(chunk) || !identical(meshNode.mesh, source)) {
      return;
    }
    StreamingDiagnostics.sync(chunk.name, 'facade-commit', () {
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
    });
  }

  void unregisterChunk(Node chunk) {
    final materials = _chunks.remove(chunk);
    if (materials != null) _ready.removeWhere(materials.contains);
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

  Future<PreprocessedMaterial?> _build(
    PhysicallyBasedMaterial wall,
    Node node,
    Node chunk,
  ) async {
    try {
      final facade = await loadFmatMaterial(shaderPath);
      final texture = wall.baseColorTexture;
      final gpuTexture = texture?.sampledTexture;
      if (gpuTexture != null) {
        facade.parameters.setTexture(
          'wall_texture',
          gpuTexture,
          sampler: texture!.sampledSampler,
        );
      }
      facade.parameters
        ..setVec4('tint', wall.baseColorFactor)
        ..setFloat('night', _night)
        ..setFloat('wetness', _wetness);
      final bounds = node.combinedWorldBounds;
      if (bounds != null) {
        final x = bounds.min.x.floor(), z = bounds.min.z.floor();
        final raw = math.sin(x * 12.9898 + z * 78.233) * 43758.5453;
        final seed = raw - raw.floor();
        FacadeProfile? profile;
        for (final candidate in profiles) {
          if (candidate.matches(bounds)) {
            profile = candidate;
            break;
          }
        }
        final style =
            profile?.style ?? (seed * 3).floor().clamp(0, 2).toDouble();
        final height = bounds.max.y - bounds.min.y;
        final floors = (height / 3.4).round().clamp(1, 30);
        facade.parameters
          ..setVec4(
            'facade_layout',
            vm.Vector4(
              bounds.min.y,
              height / floors,
              profile?.bay ?? (style == 2 ? 3.3 : 2.7),
              style.toDouble(),
            ),
          )
          ..setFloat('variation', profile?.variation ?? seed)
          ..setVec2(
            'facade_center',
            vm.Vector2(
              (bounds.min.x + bounds.max.x) / 2,
              (bounds.min.z + bounds.max.z) / 2,
            ),
          );
      }
      if (bounds != null) {
        for (final profile in profiles) {
          if (!profile.matches(bounds)) continue;
          facade.parameters
            ..setVec4('custom_tint', profile.tint)
            ..setVec4('entrance', profile.entrance);
          break;
        }
      }
      final materials = _chunks[chunk];
      if (materials == null) return null;
      materials.add(facade);
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
