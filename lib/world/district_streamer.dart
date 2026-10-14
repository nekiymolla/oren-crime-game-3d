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
    this.onChunkLoaded,
  });

  /// Чанк попал в сцену — для систем, которым нужно его содержимое
  /// (суточный цикл ищет в нём материалы окон).
  void Function(Node chunk)? onChunkLoaded;

  final Scene scene;
  final DistrictManifest manifest;
  final int radiusCells;
  final VegetationBatch vegetation;

  final Map<String, Node> _loaded = {};
  final Set<String> _loading = {};

  /// Чанки, для которых уже раскидали деревья (см. vegetation.dart) — не
  /// сажаем второй раз, если игрок уходит и возвращается: посаженные деревья
  /// остаются в общем InstancedMesh даже после выгрузки самого чанка. Те,
  /// что встали на геометрию ещё не загруженного соседа, выкорчёвываются при
  /// его загрузке (см. updateAroundPosition).
  final Set<String> _vegetationScattered = {};

  /// Пересчитывает нужный набор чанков и догружает/выгружает разницу.
  /// Дёшево звать каждый кадр — без изменения позиции ничего не делает
  /// (манифест — не больше нескольких десятков ячеек). Возвращает Future,
  /// который завершается, когда чанки, запрошенные ИМЕННО этим вызовом,
  /// реально попали в сцену — обычный per-tick вызов (см. Game.tick())
  /// его не ждёт (fire-and-forget, как и раньше), а самый первый вызов из
  /// Game.load() ждёт явно: раньше геометрия здания могла физически не
  /// успеть прогрузиться к моменту, когда пешеходы на первом кадре уже
  /// выбирали себе первую цель и рейкастили edge на проходимость — путь
  /// оказывался ошибочно "открыт" просто потому, что дома ещё не было в
  /// сцене (см. PedestrianSystem._isEdgePassable, BUGS.md).
  Future<void> updateAroundPosition(vm.Vector3 worldPosition) async {
    final wanted = _wantedChunkIds(worldPosition);

    for (final id in _loaded.keys.toList()) {
      if (!wanted.contains(id)) {
        scene.remove(_loaded[id]!);
        _loaded.remove(id);
      }
    }

    final pending = <Future<void>>[];
    for (final chunk in manifest.cells) {
      if (!wanted.contains(chunk.id)) continue;
      if (_loaded.containsKey(chunk.id) || _loading.contains(chunk.id)) continue;

      _loading.add(chunk.id);
      pending.add(
        loadDistrictChunk(chunk).then((node) {
          _loading.remove(chunk.id);
          _loaded[chunk.id] = node;
          // Здания/дороги внутри чанка не меняются, пока он смонтирован
          // (снимается тем же scene.remove(), что и добавлялся) — безопасный
          // случай для shadowStatic: движок кеширует тень вместо перекодирования
          // всех caster'ов заново каждый кадр (см. flutter_scene-performance
          // skill). Не наследуется детьми — ставим на каждый меш-узел отдельно.
          for (final meshNode in node.meshNodes) {
            meshNode.shadowStatic = true;
          }
          scene.add(node);
          onChunkLoaded?.call(node);

          // Деревья сажаются навсегда, и посаженные раньше (когда этого чанка
          // ещё не было в сцене) могли встать туда, где у него дом или
          // дорога — меши выходят за границы своей ячейки. Проверяем только
          // те, что попадают в bbox чанка с запасом на крону.
          final bounds = node.combinedWorldBounds;
          vegetation.removeTreesWhere((position, scale) {
            final radius = treeCanopyRadius * scale;
            if (bounds != null &&
                (position.x < bounds.min.x - radius ||
                    position.x > bounds.max.x + radius ||
                    position.z < bounds.min.z - radius ||
                    position.z > bounds.max.z + radius)) {
              return false;
            }
            return !isTreeSpotClear([node], position.x, position.z, radius);
          });

          if (_vegetationScattered.add(chunk.id)) {
            scatterTreesForChunk(
              vegetation: vegetation,
              obstacleRoots: _loaded.values,
              cellCenter: vm.Vector2(
                (chunk.cellX + 0.5) * manifest.cellSizeMeters,
                (chunk.cellZ + 0.5) * manifest.cellSizeMeters,
              ),
              cellSizeMeters: manifest.cellSizeMeters,
            );
          }
        }),
      );
    }
    if (pending.isNotEmpty) await Future.wait(pending);
  }

  /// Загруженные чанки, чей мировой bounding box пересекается с [box] —
  /// добавляет их в [out] (список переиспользуется вызывающим, чтобы не
  /// аллоцировать каждый кадр). Нужно, чтобы рейкасты персонажа обходили не
  /// весь граф сцены, а один-два ближних чанка (см.
  /// CharacterCollisionField): каждый `raycastNode` иначе считает обратную
  /// матрицу и тест ограничивающего объёма на КАЖДЫЙ узел сцены.
  ///
  /// Чанк без вычислимых границ (`combinedWorldBounds == null` — движок так
  /// сообщает "считать всегда видимым") попадает в список безусловно:
  /// пропустить его значило бы потерять коллизии, а это хуже любой экономии.
  void collectChunksOverlapping(vm.Aabb3 box, List<Node> out) {
    for (final chunk in _loaded.values) {
      final bounds = chunk.combinedWorldBounds;
      if (bounds == null || bounds.intersectsWithAabb3(box)) out.add(chunk);
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
