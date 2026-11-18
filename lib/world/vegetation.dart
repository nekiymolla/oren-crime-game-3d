import '../vehicles/vehicle_sweep.dart';
import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'tree_geometry.dart';
import 'tree_collision.dart';

/// Процедурная растительность. В реальных OSM-данных Южного района
/// отдельные деревья почти не размечены (see PROGRESS.md — natural=tree
/// нашлось 0 штук на весь квартал), поэтому открытые дворы/парки
/// засаживаем сами, а не ждём, пока их кто-то нанесёт на карту.
///
/// Все стволы во всей игре — один InstancedMesh (один draw call), все
/// кроны — второй; добавление дерева — просто ещё одна пара инстансов, а
/// не новый узел сцены (см. flutter_scene-procedural skill).
class VegetationBatch {
  factory VegetationBatch({int maxTrees = 220}) {
    final tree = buildDeciduousTree(
      leavesPerCluster: maxTrees <= 80
          ? 24
          : maxTrees <= 150
          ? 32
          : 42,
    );
    MeshGeometry geometry(TreeMeshData data) => MeshGeometry.fromArrays(
      positions: data.vertexPositions,
      normals: data.vertexNormals,
      colors: data.vertexColors,
      retainCpuData: false,
    );
    return VegetationBatch._(
      maxTrees,
      InstancedMesh(
        geometry: geometry(tree.branches),
        material: PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4.all(1)
          ..roughnessFactor = 0.96,
      ),
      InstancedMesh(
        geometry: geometry(tree.leaves),
        material: PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4.all(1)
          ..doubleSided = true
          ..roughnessFactor = 0.95,
      ),
    );
  }

  VegetationBatch._(this.maxTrees, this.trunks, this.canopies);

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
  double Function(double, double)? groundHeightAt;
  bool Function(double x, double z, double radius)? groundClearance;
  final List<vm.Vector3> _treePositions = [];
  final List<double> _treeScales = [];

  int get treeCount => _treePositions.length;

  Node? _node;
  bool _shadowCacheDirty = false;

  late final vm.Vector4 _canopyGreen =
      (canopies.material as PhysicallyBasedMaterial).baseColorFactor.clone();
  double _appliedSnow = 0.0;

  /// Снег на кронах (0..1, см. WeatherParams.snowCover): зелень уходит к
  /// белому. Один общий материал — одна правка на все деревья.
  void setSnowCover(double cover) {
    if ((cover - _appliedSnow).abs() < 0.01) return;
    _appliedSnow = cover;
    final white = vm.Vector4(0.85, 0.88, 0.92, 1.0);
    (canopies.material as PhysicallyBasedMaterial).vertexColorWeight =
        1.0 - cover;
    (canopies.material as PhysicallyBasedMaterial).baseColorFactor =
        _canopyGreen + (white - _canopyGreen) * cover;
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
    position = vm.Vector3(
      position.x,
      groundHeightAt?.call(position.x, position.z) ?? position.y,
      position.z,
    );
    if (_treePositions.length >= maxTrees) return;
    // Leave room for the actual crown, rather than stacking branches
    // from neighbouring cells on top of each other.
    for (var i = 0; i < _treePositions.length; i++) {
      final reach = treeCanopyRadius * (scale + _treeScales[i]) * 0.8;
      if ((position - _treePositions[i]).length2 < reach * reach) return;
    }
    _treePositions.add(position.clone());
    _treeScales.add(scale);
    _markShadowCacheDirty();
    final yaw = math.sin(position.x * 12.9898 + position.z * 78.233) * math.pi;
    final transform = vm.Matrix4.compose(
      position,
      vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw),
      vm.Vector3.all(scale),
    );
    trunks.addInstance(transform);
    canopies.addInstance(transform);
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

  /// Trunk-only collision query for walking and the player's vehicle.
  VehicleSweepHit? sweepVehicleTrunks(
    vm.Vector3 position,
    vm.Vector3 displacement,
    double oldHeading,
    double newHeading,
    double halfWidth,
    double halfLength,
  ) {
    VehicleSweepHit? nearest;
    final reach =
        math.sqrt(halfWidth * halfWidth + halfLength * halfLength) +
        displacement.length +
        1;
    for (var i = 0; i < _treePositions.length; i++) {
      final p = _treePositions[i], scale = _treeScales[i];
      if ((p.x - position.x).abs() > reach ||
          (p.z - position.z).abs() > reach ||
          position.y + .5 < p.y ||
          position.y + .5 > p.y + treeTrunkHeight * scale) {
        continue;
      }
      final hit = sweepVehicleCircle(
        position: position,
        displacement: displacement,
        oldHeading: oldHeading,
        newHeading: newHeading,
        halfWidth: halfWidth,
        halfLength: halfLength,
        circle: p,
        radius: treeTrunkRadius * scale,
      );
      if (hit != null && (nearest == null || hit.fraction < nearest.fraction)) {
        nearest = hit;
      }
    }
    return nearest;
  }

  TreeTrunkHit? castTrunks(
    vm.Vector3 origin,
    vm.Vector3 direction,
    double maxDistance, {
    double sweepRadius = 0,
  }) {
    if (direction.x * direction.x + direction.z * direction.z < 1e-10) {
      return null;
    }
    TreeTrunkHit? nearest;
    for (var i = 0; i < _treePositions.length; i++) {
      final root = _treePositions[i];
      final reach =
          maxDistance + treeTrunkRadius * _treeScales[i] + sweepRadius;
      if ((root.x - origin.x).abs() > reach ||
          (root.z - origin.z).abs() > reach) {
        continue;
      }
      final hit = raycastTreeTrunk(
        origin: origin,
        direction: direction,
        maxDistance: nearest?.distance ?? maxDistance,
        root: root,
        scale: _treeScales[i],
        sweepRadius: sweepRadius,
      );
      if (hit != null) nearest = hit;
    }
    return nearest;
  }

  void _markShadowCacheDirty() {
    _shadowCacheDirty = true;
    _node?.shadowStatic = false;
  }
}

/// Консервативный радиус кроны нового дерева масштаба 1 — по нему
/// проверяется, что крона не влезает в стену дома или не висит над дорогой.
const double treeCanopyRadius = 3.1;

/// Свободно ли место под дерево в точке ([x], [z]) с кроной [radius]: пять
/// вертикальных лучей (ствол + четыре края кроны) по каждому из [roots] не
/// должны ничего найти. Хватит одного попадания — здание, дорога, тротуар.
///
/// Именно по всем загруженным чанкам, а не только по "своему": меши
/// раскладываются по ячейкам по центру bbox'а (grid_split.mjs), так что дом
/// или длинная дорога из соседней ячейки физически лежат и в этой.
bool isTreeSpotClear(Iterable<Node> roots, double x, double z, double radius) {
  const offsets = [
    (0.0, 0.0),
    (1.0, 0.0),
    (-1.0, 0.0),
    (0.0, 1.0),
    (0.0, -1.0),
  ];
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
  bool Function(double x, double z, double radius)? groundClearance,
}) {
  final rng = random ?? math.Random();
  final half = cellSizeMeters / 2;
  for (var i = 0; i < attempts; i++) {
    final x = cellCenter.x + (rng.nextDouble() * 2 - 1) * half;
    final z = cellCenter.y + (rng.nextDouble() * 2 - 1) * half;
    final scale = 0.8 + rng.nextDouble() * 0.5;
    final clear =
        groundClearance?.call(x, z, treeCanopyRadius * scale) ??
        isTreeSpotClear(obstacleRoots, x, z, treeCanopyRadius * scale);
    if (!clear) {
      continue;
    }
    vegetation.addTree(vm.Vector3(x, 0, z), scale: scale);
  }
}
