import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'district.dart';
import 'vegetation.dart';

/// Держит в сцене только чанки района в радиусе [radiusCells] ячеек вокруг
/// игрока — остальные не загружены и не участвуют ни в рендере, ни в
/// raycastNode-коллизиях (последние обходят все узлы дерева сцены на каждый
/// луч, так что общий размер загруженной геометрии стоит независимо от
/// того, видна ли она — см. PROGRESS.md, диагностика лагов).
class DistrictStreamer {
  DistrictStreamer({
    required this.scene,
    required this.manifest,
    required this.radiusCells,
    required this.vegetation,
  });

  final Scene scene;
  final DistrictManifest manifest;
  final int radiusCells;
  final VegetationBatch vegetation;

  final Map<String, Node> _loaded = {};
  final Set<String> _loading = {};

  /// Чанки, для которых уже раскидали деревья (см. vegetation.dart) — не
  /// сажаем второй раз, если игрок уходит и возвращается: посаженные деревья
  /// остаются в общем InstancedMesh даже после выгрузки самого чанка (их
  /// координаты не зависят от того, загружен ли рядом лежащий район).
  final Set<String> _vegetationScattered = {};

  /// Пересчитывает нужный набор чанков и догружает/выгружает разницу.
  /// Дёшево звать каждый кадр — без изменения позиции ничего не делает
  /// (манифест — не больше нескольких десятков ячеек).
  void updateAroundPosition(vm.Vector3 worldPosition) {
    final wanted = _wantedChunkIds(worldPosition);

    for (final id in _loaded.keys.toList()) {
      if (!wanted.contains(id)) {
        scene.remove(_loaded[id]!);
        _loaded.remove(id);
      }
    }

    for (final chunk in manifest.cells) {
      if (!wanted.contains(chunk.id)) continue;
      if (_loaded.containsKey(chunk.id) || _loading.contains(chunk.id)) continue;

      _loading.add(chunk.id);
      loadDistrictChunk(chunk).then((node) {
        _loading.remove(chunk.id);
        _loaded[chunk.id] = node;
        scene.add(node);

        if (_vegetationScattered.add(chunk.id)) {
          scatterTreesForChunk(
            vegetation: vegetation,
            chunkRoot: node,
            cellCenter: vm.Vector2(
              (chunk.cellX + 0.5) * manifest.cellSizeMeters,
              (chunk.cellZ + 0.5) * manifest.cellSizeMeters,
            ),
            cellSizeMeters: manifest.cellSizeMeters,
          );
        }
      });
    }
  }

  Set<String> _wantedChunkIds(vm.Vector3 pos) {
    final centerX = manifest.cellIndexOf(pos.x);
    final centerZ = manifest.cellIndexOf(pos.z);
    return {
      for (final chunk in manifest.cells)
        if ((chunk.cellX - centerX).abs() <= radiusCells &&
            (chunk.cellZ - centerZ).abs() <= radiusCells)
          chunk.id,
    };
  }
}
