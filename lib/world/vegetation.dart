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
  int _treeCount = 0;

  Node? _node;
  bool _shadowCacheDirty = false;

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
    if (_treeCount >= maxTrees) return;
    _treeCount++;
    _shadowCacheDirty = true;
    _node?.shadowStatic = false;
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
}

/// Раскидывает деревья по [chunkRoot] случайными точками в квадрате
/// [cellSizeMeters] с центром в [cellCenter] — но только там, где
/// вертикальный [raycastNode] по САМОМУ ЭТОМУ чанку ничего не находит
/// (то есть в местах, где OSM ничего не разметил и показывается только
/// плейсхолдер-земля, см. terrain.dart) — гарантированно не в зданиях и
/// не на дорогах, без отдельного анализа footprint'ов в пайплайне.
void scatterTreesForChunk({
  required VegetationBatch vegetation,
  required Node chunkRoot,
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
    final hit = raycastNode(
      chunkRoot,
      vm.Ray.originDirection(vm.Vector3(x, 50, z), vm.Vector3(0, -1, 0)),
      maxDistance: 100,
    );
    if (hit != null) continue; // тут уже что-то есть (здание, дорога, ...)
    vegetation.addTree(vm.Vector3(x, 0, z), scale: 0.8 + rng.nextDouble() * 0.5);
  }
}
