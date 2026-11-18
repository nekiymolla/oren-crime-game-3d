import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../world/district_streamer.dart';
import 'character_motion.dart';

/// Коллизионная область персонажа: решает, по КАКИМ узлам вообще идут его
/// лучи. Вторая половина экономии кадра (первая — число лучей, см.
/// [CharacterMotion]).
///
/// Встроенный `ThirdPersonControllerComponent` кидал каждый луч от корня
/// сцены: девять загруженных чанков района это сотни меш-узлов, и на каждый
/// узел `raycastNode` считает обратную матрицу и тест ограничивающего объёма —
/// девять раз за кадр (замеры в PROGRESS.md: 14 мс из 16.6 мс бюджета).
/// Сузить область встроенный не даёт, только `groundLayerMask` — а маска
/// экономит лишь проверку меша, обход дерева всё равно происходит целиком
/// (см. `_walk` в raycast.dart: в детей он спускается независимо от маски).
/// Поэтому здесь не маска, а **явный узкий список корней обхода**: только те
/// чанки, чей мировой bounding box вообще пересекается с коробкой вокруг
/// персонажа (обычно один чанк из девяти), плюс подвижные/локальные
/// коллайдеры (машины) в пределах досягаемости.
///
/// Отбор идёт по РЕАЛЬНОМУ bounding box'у чанка (`Node.combinedWorldBounds`),
/// а не по прямоугольнику ячейки из манифеста: grid_split.mjs раскладывает
/// меши по ячейкам по центру их bbox'а, так что длинный меш дороги физически
/// выходит за границы своей ячейки. Bounding box это учитывает, границы
/// ячейки — нет.
class CharacterCollisionField {
  CharacterCollisionField({
    required this.districtStreamer,
    this.additionalRaycast,
    this.probeRadiusMeters = 2.0,
    this.probeBelowMeters = 1.5,
    this.probeAboveMeters = 2.5,
  });

  /// Источник загруженных чанков района — вся статическая коллизионная
  /// геометрия игры (здания, дороги) лежит в них.
  final DistrictStreamer districtStreamer;
  final CharacterRaycaster? additionalRaycast;

  /// Полуразмер коробки отбора вокруг персонажа. С запасом покрывает и луч
  /// на землю, и кольцо лучей обхода (радиус тела 0.5 +
  /// смещение за кадр ~0.14 при беге), и смещение персонажа внутри кадра
  /// после [refresh] — отбор дешевле луча, экономить на запасе нечего, а
  /// недобор означал бы проход сквозь стену.
  final double probeRadiusMeters;
  final double probeBelowMeters;
  final double probeAboveMeters;

  final List<Node> _candidates = [];
  final List<_ColliderSource> _sources = [];
  final vm.Aabb3 _probeBox = vm.Aabb3();

  /// Сколько корней обхода отобрано в последнем [refresh] — для отладки и
  /// тестов ("сузилось ли вообще").
  int get candidateCount => _candidates.length;

  /// Дополнительные коллайдеры помимо района: машины игрока/декоративные,
  /// патрульные машины. Источник — колбэк, потому что набор меняется в
  /// рантайме (полиция спавнится и исчезает по звёздам розыска).
  /// [radiusMeters] — грубый радиус габарита, чтобы отсечь далёкие без
  /// разбора их поддеревьев.
  void addColliderSource(
    Iterable<Node> Function() nodes, {
    double radiusMeters = 3.0,
  }) {
    _sources.add(_ColliderSource(nodes, radiusMeters));
  }

  /// Пересобирает список корней обхода вокруг [center]. Зовётся раз в кадр
  /// из Game.tick(), то есть ДО тика компонентов (SceneView.onTick сначала
  /// отдаёт тик игре, потом рисует сцену) — лучи в этом же кадре уже видят
  /// свежий список.
  void refresh(vm.Vector3 center) {
    _candidates.clear();
    _probeBox.setCenterAndHalfExtents(
      vm.Vector3(
        center.x,
        center.y + (probeAboveMeters - probeBelowMeters) / 2,
        center.z,
      ),
      vm.Vector3(
        probeRadiusMeters,
        (probeAboveMeters + probeBelowMeters) / 2,
        probeRadiusMeters,
      ),
    );
    districtStreamer.collectChunksOverlapping(_probeBox, _candidates);

    for (final source in _sources) {
      for (final node in source.nodes()) {
        final position = node.globalTransform.getTranslation();
        final dx = position.x - center.x;
        final dz = position.z - center.z;
        final reach = probeRadiusMeters + source.radiusMeters;
        if (dx * dx + dz * dz <= reach * reach) _candidates.add(node);
      }
    }
  }

  /// Луч по отобранным корням — то, что подставляется в
  /// [CharacterMotion.raycast].
  CharacterRayHit? cast(
    vm.Vector3 origin,
    vm.Vector3 direction,
    double maxDistance,
  ) {
    final ray = vm.Ray.originDirection(origin, direction);
    SceneRaycastHit? nearest;
    for (final root in _candidates) {
      final hit = raycastNode(root, ray, maxDistance: maxDistance);
      if (hit != null && (nearest == null || hit.distance < nearest.distance)) {
        nearest = hit;
      }
    }
    final additional = additionalRaycast?.call(
      origin,
      direction,
      nearest?.distance ?? maxDistance,
    );
    if (additional != null) return additional;
    if (nearest == null) return null;
    return CharacterRayHit(
      distance: nearest.distance,
      normal: nearest.worldNormal,
    );
  }
}

class _ColliderSource {
  _ColliderSource(this.nodes, this.radiusMeters);

  final Iterable<Node> Function() nodes;
  final double radiusMeters;
}
