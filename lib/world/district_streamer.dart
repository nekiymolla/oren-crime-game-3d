import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'district.dart';
import 'vegetation.dart';
import 'streaming_work.dart';
import 'streaming_diagnostics.dart';

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
    this.onChunkPrepare,
    this.onChunkLoaded,
    this.onChunkUnloaded,
  });

  /// Подготовка материалов до добавления чанка в сцену.
  FutureOr<void> Function(Node chunk)? onChunkPrepare;

  /// Чанк добавлен в сцену: можно регистрировать окна и мокрые дороги.
  FutureOr<void> Function(Node chunk)? onChunkLoaded;
  void Function(Node chunk)? onChunkUnloaded;

  final Scene scene;
  final DistrictManifest manifest;
  final int radiusCells;
  final VegetationBatch vegetation;

  final Map<String, Node> _loaded = {};
  final Map<String, Node> _preparing = {};
  final Map<String, Future<void>> _loading = {};
  late final _center = StreamingCenter(cellSize: manifest.cellSizeMeters);
  final _work = StreamingWork<Node?>(
    yieldToFrame: () => SchedulerBinding.instance.endOfFrame,
  );
  Set<String> _wanted = {};
  Future<void>? _currentUpdate;

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
  Future<void> updateAroundPosition(vm.Vector3 worldPosition) {
    if (!_center.update(worldPosition.x, worldPosition.z) &&
        _currentUpdate != null) {
      return _currentUpdate!;
    }
    final wanted = _wanted = _wantedChunkIds(_center.cell);

    for (final id in _loaded.keys.toList()) {
      if (!wanted.contains(id)) {
        onChunkUnloaded?.call(_loaded[id]!);
        scene.remove(_loaded[id]!);
        _loaded.remove(id);
      }
    }

    for (final id in _preparing.keys.toList()) {
      if (!wanted.contains(id)) {
        onChunkUnloaded?.call(_preparing.remove(id)!);
      }
    }

    final pending = <Future<void>>[];
    final cells = manifest.cells.where((c) => wanted.contains(c.id)).toList()
      ..sort((a, b) {
        final (cx, cz) = _center.cell;
        final da =
            (a.cellX - cx) * (a.cellX - cx) + (a.cellZ - cz) * (a.cellZ - cz);
        final db =
            (b.cellX - cx) * (b.cellX - cx) + (b.cellZ - cz) * (b.cellZ - cz);
        return da.compareTo(db);
      });
    for (final chunk in cells) {
      if (_loaded.containsKey(chunk.id)) continue;
      final existing = _loading[chunk.id];
      if (existing != null) {
        pending.add(existing);
        continue;
      }
      final task = _work
          .schedule(chunk.id, () async {
            if (!_wanted.contains(chunk.id)) return null;
            final node = await loadDistrictChunk(chunk);
            if (!_wanted.contains(chunk.id)) return null;
            _preparing[chunk.id] = node;
            try {
              await onChunkPrepare?.call(node);
              if (!_wanted.contains(chunk.id) ||
                  !identical(_preparing[chunk.id], node)) {
                return null;
              }
            } catch (_) {
              onChunkUnloaded?.call(node);
              rethrow;
            } finally {
              if (!_wanted.contains(chunk.id)) onChunkUnloaded?.call(node);
              _preparing.remove(chunk.id);
            }
            _loaded[chunk.id] = node;
            // Здания/дороги внутри чанка не меняются, пока он смонтирован
            // (снимается тем же scene.remove(), что и добавлялся) — безопасный
            // случай для shadowStatic: движок кеширует тень вместо перекодирования
            // всех caster'ов заново каждый кадр (см. flutter_scene-performance
            // skill). Не наследуется детьми — ставим на каждый меш-узел отдельно.
            StreamingDiagnostics.sync(chunk.id, 'attach', () {
              for (final meshNode in node.meshNodes) {
                meshNode.shadowStatic = true;
              }
              scene.add(node);
            });
            await onChunkLoaded?.call(node);
            if (!_wanted.contains(chunk.id) ||
                !identical(_loaded[chunk.id], node)) {
              return null;
            }

            // Деревья сажаются навсегда, и посаженные раньше (когда этого чанка
            // ещё не было в сцене) могли встать туда, где у него дом или
            // дорога — меши выходят за границы своей ячейки. Проверяем только
            // те, что попадают в bbox чанка с запасом на крону.
            final bounds = node.combinedWorldBounds;
            if (vegetation.groundClearance == null) {
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
            }

            if (_vegetationScattered.add(chunk.id)) {
              StreamingDiagnostics.sync(
                chunk.id,
                'vegetation',
                () => scatterTreesForChunk(
                  vegetation: vegetation,
                  random: math.Random(
                    chunk.cellX * 73856093 ^ chunk.cellZ * 19349663,
                  ),
                  obstacleRoots: _loaded.values,
                  groundClearance: vegetation.groundClearance,
                  cellCenter: vm.Vector2(
                    (chunk.cellX + 0.5) * manifest.cellSizeMeters,
                    (chunk.cellZ + 0.5) * manifest.cellSizeMeters,
                  ),
                  cellSizeMeters: manifest.cellSizeMeters,
                ),
              );
            }
            return node;
          })
          .then<void>((_) {})
          .whenComplete(() {
            _loading.remove(chunk.id);
            // Игрок мог вернуться к чанку, пока отменялась его подготовка.
            // Следующий tick должен повторить запрос даже в той же ячейке.
            if (_wanted.contains(chunk.id) && !_loaded.containsKey(chunk.id)) {
              _center.reset();
            }
          });
      _loading[chunk.id] = task;
      pending.add(task);
    }
    return _currentUpdate = Future.wait(pending).then<void>((_) {}).catchError((
      Object error,
      StackTrace stack,
    ) {
      _center.reset();
      Error.throwWithStackTrace(error, stack);
    });
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

  Set<String> _wantedChunkIds((int, int) center) {
    final (centerX, centerZ) = center;
    return {
      for (final chunk in manifest.cells)
        if ((chunk.cellX - centerX).abs() <= radiusCells &&
            (chunk.cellZ - centerZ).abs() <= radiusCells)
          chunk.id,
    };
  }
}
