import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Процедурная растительность. В реальных OSM-данных Южного района
/// отдельные деревья почти не размечены (see PROGRESS.md — natural=tree
/// нашлось 0 штук на весь квартал), поэтому открытые дворы/парки
/// засаживаем сами, а не ждём, пока их кто-то нанесёт на карту.
///
/// Все стволы во всей игре — один InstancedMesh (один draw call), все
/// кроны — второй; добавление дерева — просто ещё одна пара инстансов, а
/// не новый узел сцены (см. flutter_scene-procedural skill).
class VegetationBatch {
  VegetationBatch({this.maxTrees = 220})
    : trunks = InstancedMesh(
        geometry: CylinderGeometry(bottomRadius: 0.15, topRadius: 0.12, height: _trunkHeight),
        material: PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.30, 0.20, 0.12, 1.0)
          ..roughnessFactor = 0.9,
      ),
      canopies = InstancedMesh(
        geometry: IcosphereGeometry(radius: 1.0, subdivisions: 1),
        material: PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.16, 0.36, 0.14, 1.0)
          ..roughnessFactor = 0.95,
      );

  static const double _trunkHeight = 2.2;

  /// Деревья сажаются навсегда (см. DistrictStreamer — не убираются вместе
  /// с выгрузкой чанка) и без потолка их число росло бы весь сеанс по мере
  /// исследования района, отсюда прогрессирующая просадка FPS с каждой
  /// новой посещённой ячейкой (см. PROGRESS.md). Жёсткий кап держит
  /// стоимость растительности постоянной независимо от того, сколько
  /// исследовано. Значение приходит из пресета качества (quality.json) —
  /// 220 здесь только как значение по умолчанию для тестов и прямых вызовов.
  final int maxTrees;

  final InstancedMesh trunks;
  final InstancedMesh canopies;

  /// Корни стволов посаженных деревьев — индекс совпадает с индексом
  /// инстанса в [trunks]/[canopies]. Нужны, чтобы выкорчевать дерево,
  /// оказавшееся внутри дома/дороги из чанка, догруженного позже (см.
  /// [removeTreesWhere]).
  final List<vm.Vector3> _treePositions = [];
  final List<double> _treeScales = [];

  int get treeCount => _treePositions.length;

  Node? _node;
  bool _shadowCacheDirty = false;

  late final vm.Vector4 _canopyGreen = (canopies.material as PhysicallyBasedMaterial).baseColorFactor.clone();
  double _appliedSnow = 0.0;

  /// Снег на кронах (0..1, см. WeatherParams.snowCover): зелень уходит к
  /// белому. Один общий материал — одна правка на все деревья.
  void setSnowCover(double cover) {
    if ((cover - _appliedSnow).abs() < 0.01) return;
    _appliedSnow = cover;
    final white = vm.Vector4(0.85, 0.88, 0.92, 1.0);
    (canopies.material as PhysicallyBasedMaterial).baseColorFactor = _canopyGreen + (white - _canopyGreen) * cover;
  }

  /// Один узел на всю растительность игры — держит оба InstancedMesh.
  /// Не привязан к чанкам: инстансы внутри можно добавлять/убирать, сам
  /// узел из сцены не удаляется.
  Node buildNode() {
    final node = Node()
      ..addComponent(InstancedMeshComponent(trunks))
      ..addComponent(InstancedMeshComponent(canopies));
    // Деревья не двигаются, но по умолчанию перекодировались в карту теней
    // каждый кадр. Замер на RMX5303 (19.09.2026): один этот флаг снял 46.1 мс
    // raster из 149.7 — почти столько же, сколько полное удаление деревьев
    // из сцены (то есть платили мы не за их отрисовку, а именно за тени).
    node.shadowStatic = true;
    _node = node;
    return node;
  }

  /// Контракт shadowStatic требует, чтобы содержимое узла не менялось, а
  /// деревья досаживаются по мере стриминга чанков. Поэтому на время посадки
  /// флаг снимается, а [commitShadowCache] (раз в кадр из Game.tick) ставит
  /// его обратно — движок перестраивает кэш уже с новыми деревьями. Без
  /// этого у досаженных деревьев не было бы теней до конца сессии.
  void commitShadowCache() {
    if (!_shadowCacheDirty) return;
    _shadowCacheDirty = false;
    _node?.shadowStatic = true;
  }

  /// Добавляет дерево в [position] (корень ствола на уровне земли).
  /// [scale] — случайный разброс размера для естественности. Не делает
  /// ничего сверх [maxTrees] — см. его комментарий.
  void addTree(vm.Vector3 position, {double scale = 1.0}) {
    if (_treePositions.length >= maxTrees) return;
    _treePositions.add(position.clone());
    _treeScales.add(scale);
    _markShadowCacheDirty();
    trunks.addInstance(
      vm.Matrix4.compose(
        position + vm.Vector3(0, _trunkHeight * scale / 2, 0),
        vm.Quaternion.identity(),
        vm.Vector3.all(scale),
      ),
    );
    canopies.addInstance(
      vm.Matrix4.compose(
        position + vm.Vector3(0, (_trunkHeight + 0.7) * scale, 0),
        vm.Quaternion.identity(),
        vm.Vector3(scale, scale * 1.1, scale),
      ),
    );
  }

  /// Убирает деревья, для которых [test] (корень ствола, масштаб) вернул
  /// true. Освободившиеся места под [maxTrees] достаются следующим посадкам.
  void removeTreesWhere(bool Function(vm.Vector3 position, double scale) test) {
    // С конца: removeInstanceAt сдвигает индексы всех следующих инстансов.
    for (var i = _treePositions.length - 1; i >= 0; i--) {
      if (!test(_treePositions[i], _treeScales[i])) continue;
      _treePositions.removeAt(i);
      _treeScales.removeAt(i);
      trunks.removeInstanceAt(i);
      canopies.removeInstanceAt(i);
      _markShadowCacheDirty();
    }
  }

  void _markShadowCacheDirty() {
    _shadowCacheDirty = true;
    _node?.shadowStatic = false;
  }
}

/// Радиус кроны дерева масштаба 1 (IcosphereGeometry радиуса 1.0) — по нему
/// проверяется, что крона не влезает в стену дома или не висит над дорогой.
const double treeCanopyRadius = 1.0;

/// Свободно ли место под дерево в точке ([x], [z]) с кроной [radius]: пять
/// вертикальных лучей (ствол + четыре края кроны) по каждому из [roots] не
/// должны ничего найти. Хватит одного попадания — здание, дорога, тротуар.
///
/// Именно по всем загруженным чанкам, а не только по "своему": меши
/// раскладываются по ячейкам по центру bbox'а (grid_split.mjs), так что дом
/// или длинная дорога из соседней ячейки физически лежат и в этой.
bool isTreeSpotClear(Iterable<Node> roots, double x, double z, double radius) {
  const offsets = [(0.0, 0.0), (1.0, 0.0), (-1.0, 0.0), (0.0, 1.0), (0.0, -1.0)];
  for (final root in roots) {
    for (final (dx, dz) in offsets) {
      final hit = raycastNode(
        root,
        vm.Ray.originDirection(
          vm.Vector3(x + dx * radius, 50, z + dz * radius),
          vm.Vector3(0, -1, 0),
        ),
        maxDistance: 100,
      );
      if (hit != null) return false;
    }
  }
  return true;
}

/// Раскидывает деревья случайными точками в квадрате [cellSizeMeters] с
/// центром в [cellCenter] — только там, где [isTreeSpotClear] по всем
/// [obstacleRoots] (загруженные чанки района) ничего не находит, то есть
/// там, где OSM ничего не разметил и видна только плейсхолдер-земля (см.
/// terrain.dart).
///
/// Чанки, которые загрузятся позже, этой проверкой не покрыты — их деревья
/// выкорчёвывает [DistrictStreamer] при загрузке (см. [removeTreesWhere]).
void scatterTreesForChunk({
  required VegetationBatch vegetation,
  required Iterable<Node> obstacleRoots,
  required vm.Vector2 cellCenter,
  required double cellSizeMeters,
  int attempts = 24,
  math.Random? random,
}) {
  final rng = random ?? math.Random();
  final half = cellSizeMeters / 2;
  for (var i = 0; i < attempts; i++) {
    final x = cellCenter.x + (rng.nextDouble() * 2 - 1) * half;
    final z = cellCenter.y + (rng.nextDouble() * 2 - 1) * half;
    final scale = 0.8 + rng.nextDouble() * 0.5;
    if (!isTreeSpotClear(obstacleRoots, x, z, treeCanopyRadius * scale)) continue;
    vegetation.addTree(vm.Vector3(x, 0, z), scale: scale);
  }
}
