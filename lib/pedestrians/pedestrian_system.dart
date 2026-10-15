import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../characters/character_animation.dart';
import '../characters/character_library.dart';
import '../characters/character_model.dart';
import '../weapons/ballistics.dart';
import '../weapons/player_shooting.dart';
import '../world/nav_grid.dart';
import 'pedestrian.dart';

/// Пуля попала в пешехода (см. PedestrianSystem.raycastShootable).
typedef PedestrianShotHit = ({int index, double distance, BodyZone zone});

/// Держит NPC-пешеходов вокруг игрока/машины: спавнит рядом
/// ([spawnRadius]), переселяет в кольцо [minRespawnDistance]..[spawnRadius],
/// когда отходят дальше [despawnRadius]. Ходят хаотично по навигационной
/// сетке ([nav]): не заходят в дома и на крупные дороги (см.
/// pedestrian.dart — сама ходьба проверена юнит-тестами отдельно от
/// рендера).
///
/// Рендер — анимированные модели людей из [characters] (по draw call'у на
/// человека, см. tools/assets/prepare_characters.mjs). Без библиотеки
/// моделей (юнит-тесты без GPU) — прежние капсулы одним `InstancedMesh`.
class PedestrianSystem implements ShootTargets {
  PedestrianSystem({
    required this.nav,
    this.characters,
    this.population = 16,
    this.spawnRadius = 120.0,
    this.despawnRadius = 180.0,
    this.minRespawnDistance = 70.0,
    this.walkSpeed = 1.3,
    math.Random? random,
  }) : _random = random ?? math.Random(),
       bodies = InstancedMesh(
         geometry: CapsuleGeometry(radius: _radius, height: _bodyHeight),
         material: PhysicallyBasedMaterial()
           ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
           ..roughnessFactor = 0.85,
       );

  static const double _radius = 0.3;
  static const double _bodyHeight = 0.9;
  static const double _totalHeight = _bodyHeight + _radius * 2;

  static final List<vm.Vector4> _palette = [
    vm.Vector4(0.25, 0.35, 0.75, 1.0), // синий
    vm.Vector4(0.85, 0.70, 0.20, 1.0), // жёлтый
    vm.Vector4(0.55, 0.30, 0.65, 1.0), // фиолетовый
    vm.Vector4(0.20, 0.55, 0.50, 1.0), // бирюзовый
    vm.Vector4(0.80, 0.45, 0.20, 1.0), // оранжевый
  ];

  /// Навигационная сетка района (lib/world/nav_grid.dart).
  final NavGrid nav;
  final int population;
  final double spawnRadius;
  final double despawnRadius;
  final double minRespawnDistance;
  final double walkSpeed;
  final InstancedMesh bodies;

  /// Модели людей; null — капсулы.
  final CharacterLibrary? characters;

  /// Дальше этого от игрока модель прячется (и не анимируется) — сам
  /// пешеход при этом продолжает жить (см. PROGRESS.md: существование по
  /// расстоянию отдельно от рендера).
  static const double modelVisibleDistance = 110.0;

  /// Камера (положение и направление взгляда по горизонтали) — модели за
  /// её спиной прячутся: у скинованных мешей нет границ, движок не
  /// отсекает их по кадру и анимирует даже невидимых (см. CharacterModel).
  vm.Vector3? viewPosition;
  vm.Vector3? viewForward;

  /// Насколько позади камеры модель ещё держится (корпус, тень на экране).
  static const double _behindViewMargin = 4.0;

  final math.Random _random;
  final List<Pedestrian> _pedestrians = [];

  /// Модель пешехода с тем же номером (пусто без [characters]).
  final List<CharacterModel> _models = [];

  /// Где пешеход был кадр назад — для скорости, от которой зависит клип.
  final List<vm.Vector3> _lastPositions = [];
  final Node _root = Node();
  bool _spawned = false;

  /// Ниже которой наезд машиной не считается — стоящая/едва катящаяся
  /// машина у пешехода не в счёт, только реальный удар.
  static const double hitSpeedThreshold = 3.0;
  static const double _hitRadius = 1.0;

  Node buildNode() {
    if (characters == null) _root.addComponent(InstancedMeshComponent(bodies));
    return _root;
  }

  /// Позиции пешеходов — перед ними тормозит трафик (см. lib/traffic/).
  Iterable<vm.Vector3> get positions => _pedestrians.map((p) => p.position);

  /// Радиус капсулы пешехода — для препятствий трафика.
  static const double bodyRadius = _radius;

  /// Полный рост пешехода — для попаданий и автоприцела.
  static const double bodyHeight = _totalHeight;

  /// Тело убитого убирается (пешеход переселяется), только если лежит
  /// дольше этого и игрок не ближе [_bodyCleanupDistance] — на глазах
  /// трупы не исчезают.
  static const double _bodyCleanupSeconds = 45.0;
  static const double _bodyCleanupDistance = 60.0;

  /// Пуля по лучу: ближайший живой стоящий пешеход, в которого попадает
  /// луч из [origin] вдоль единичного [direction] не дальше [maxDistance].
  @override
  PedestrianShotHit? raycastShootable(vm.Vector3 origin, vm.Vector3 direction, double maxDistance) {
    PedestrianShotHit? best;
    for (var i = 0; i < _pedestrians.length; i++) {
      final pedestrian = _pedestrians[i];
      if (!pedestrian.isShootable) continue;
      final limit = best?.distance ?? maxDistance;
      final t = rayVerticalCapsule(origin, direction, limit, pedestrian.position, _radius, _totalHeight);
      if (t == null) continue;
      final hitY = origin.y + direction.y * t;
      best = (index: i, distance: t, zone: zoneForHitHeight(hitY - pedestrian.position.y, _totalHeight));
    }
    return best;
  }

  /// Пуля попала в пешехода [index]: урон [damage] от стрелка в [from].
  /// Возвращает true, если убит (раненый сам бежит прочь, см. takeDamage).
  @override
  bool applyShot(int index, double damage, vm.Vector3 from) {
    final pedestrian = _pedestrians[index];
    final killed = pedestrian.takeDamage(damage, from);
    if (_models.isEmpty) {
      bodies.setInstanceTransform(pedestrian.instanceIndex, _instanceTransform(pedestrian));
    } else if (!killed) {
      _models[index].play(CharacterAnim.hit, fadeSeconds: 0.08, restart: true);
    }
    return killed;
  }

  /// Выстрел в [shooter] слышно на [radius] метров: все живые рядом
  /// бегут прочь. Возвращает, сколько было свидетелей.
  @override
  int scareAround(vm.Vector3 shooter, double radius) {
    final radiusSq = radius * radius;
    var witnesses = 0;
    for (final pedestrian in _pedestrians) {
      if (pedestrian.isDead || (pedestrian.position - shooter).length2 > radiusSq) continue;
      pedestrian.scare(shooter);
      witnesses++;
    }
    return witnesses;
  }

  @override
  vm.Vector3 feetOf(int index) => _pedestrians[index].position.clone();

  @override
  TargetKind kindOf(int index) => TargetKind.pedestrian;

  /// Точки прицеливания (грудь) живых стоящих пешеходов — для
  /// автоприцела. [indices] получает их номера для [applyShot].
  @override
  void collectAimPoints(List<vm.Vector3> points, List<int> indices) {
    for (var i = 0; i < _pedestrians.length; i++) {
      final pedestrian = _pedestrians[i];
      if (!pedestrian.isShootable) continue;
      points.add(pedestrian.position + vm.Vector3(0, _totalHeight * 0.65, 0));
      indices.add(i);
    }
  }

  /// Зовётся каждый кадр из Game.tick(). Первый вызов лениво спавнит
  /// начальную популяцию вокруг [trackedPosition]. [vehiclePosition]/
  /// [vehicleSpeed] — если заданы (машина существует и её скорость выше
  /// [hitSpeedThreshold]), пешеходы в радиусе удара падают (см.
  /// Pedestrian.knockDown) и засчитываются в возвращаемое число наездов —
  /// на нём строится WantedSystem (см. lib/police).
  int update(double dt, vm.Vector3 trackedPosition, {vm.Vector3? vehiclePosition, double vehicleSpeed = 0.0}) {
    if (!_spawned) {
      _spawnInitialPopulation(trackedPosition);
      _spawned = true;
    }

    var hits = 0;
    final canHit = vehiclePosition != null && vehicleSpeed >= hitSpeedThreshold;
    final hitRadiusSq = _hitRadius * _hitRadius;
    final despawnRadiusSq = despawnRadius * despawnRadius;
    for (var i = 0; i < _pedestrians.length; i++) {
      final pedestrian = _pedestrians[i];
      advancePedestrian(
        pedestrian,
        walkable: nav.isWalkable,
        solid: nav.isBuilding,
        dt: dt,
        speed: walkSpeed,
        random: _random,
      );

      // Лежачего (и мёртвого) повторно не сбить и не засчитать второй раз
      // в розыск.
      if (canHit &&
          !pedestrian.isKnockedDown &&
          !pedestrian.isDead &&
          (pedestrian.position - vehiclePosition).length2 <= hitRadiusSq) {
        hits++;
        pedestrian.knockDown(vehiclePosition, vehicleSpeed);
      } else if ((pedestrian.position - trackedPosition).length2 > despawnRadiusSq) {
        _respawnNear(pedestrian, trackedPosition);
      } else if (pedestrian.isDead &&
          pedestrian.deadSeconds > _bodyCleanupSeconds &&
          (pedestrian.position - trackedPosition).length2 > _bodyCleanupDistance * _bodyCleanupDistance) {
        _respawnNear(pedestrian, trackedPosition);
      }

      if (_models.isEmpty) {
        bodies.setInstanceTransform(pedestrian.instanceIndex, _instanceTransform(pedestrian));
      } else {
        _updateModel(i, dt, trackedPosition);
      }
    }
    return hits;
  }

  /// Модель следует за пешеходом; клип — по состоянию и реальной скорости.
  void _updateModel(int i, double dt, vm.Vector3 trackedPosition) {
    final pedestrian = _pedestrians[i];
    final model = _models[i];
    final last = _lastPositions[i];
    final moved = math.sqrt(math.pow(pedestrian.position.x - last.x, 2) + math.pow(pedestrian.position.z - last.z, 2));
    last.setFrom(pedestrian.position);
    final eye = viewPosition;
    final forward = viewForward;
    final visible =
        (pedestrian.position - trackedPosition).length2 <= modelVisibleDistance * modelVisibleDistance &&
        (eye == null ||
            forward == null ||
            (pedestrian.position.x - eye.x) * forward.x + (pedestrian.position.z - eye.z) * forward.z > -_behindViewMargin);
    model.visible = visible;
    if (!visible) return;
    model.node.position = pedestrian.position;
    model.node.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), pedestrian.yaw);
    final lying = pedestrian.isDead || pedestrian.isKnockedDown;
    // Удар пулей доигрывается, если раненый не упал.
    final reacting = model.current == CharacterAnim.hit && !model.currentFinished && !lying;
    if (!reacting) {
      // Сбитый машиной отлетает со скоростью — это не бег; скачок за кадр
      // дальше пары метров — переселение, а не движение.
      final speed = lying || dt <= 0 || moved > 3.0 ? 0.0 : moved / dt;
      final choice = locomotionAnim(speed: speed, lying: lying);
      model.play(choice.anim, rate: choice.rate, fadeSeconds: lying ? 0.12 : 0.25);
    }
    model.update(dt);
  }

  /// Стоящий — капсула вертикально по курсу; сбитый или убитый — лежит на
  /// земле вдоль направления отлёта.
  vm.Matrix4 _instanceTransform(Pedestrian pedestrian) {
    final heading = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), pedestrian.yaw);
    if (!pedestrian.isKnockedDown && !pedestrian.isDead) {
      return vm.Matrix4.compose(
        pedestrian.position + vm.Vector3(0, _totalHeight / 2, 0),
        heading,
        vm.Vector3.all(1.0),
      );
    }
    return vm.Matrix4.compose(
      pedestrian.position + vm.Vector3(0, _radius, 0),
      heading * vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
      vm.Vector3.all(1.0),
    );
  }

  void _spawnInitialPopulation(vm.Vector3 center) {
    for (var i = 0; i < population; i++) {
      final pedestrian = Pedestrian(position: _randomSpotNear(center), yaw: _random.nextDouble() * 2 * math.pi);
      final library = characters;
      if (library == null) {
        pedestrian.instanceIndex = bodies.addInstance(
          _instanceTransform(pedestrian),
          color: _palette[_random.nextInt(_palette.length)],
        );
      } else {
        final model = library.createCivilian(_random);
        _models.add(model);
        _root.add(model.node);
      }
      _lastPositions.add(pedestrian.position.clone());
      _pedestrians.add(pedestrian);
    }
  }

  /// Водитель угнанной машины выскакивает в [door] и в панике бежит прочь
  /// от [awayFrom] (игрока). Отдельного NPC не заводим: популяция
  /// фиксирована, так что "водителем" становится самый дальний от места
  /// пешеход (его исчезновение вдали никто не видит).
  void spawnFleeingDriver(vm.Vector3 door, vm.Vector3 awayFrom) {
    if (_pedestrians.isEmpty) return;
    Pedestrian? farthest;
    var farthestSq = -1.0;
    for (final pedestrian in _pedestrians) {
      final distanceSq = (pedestrian.position - door).length2;
      if (distanceSq > farthestSq) {
        farthestSq = distanceSq;
        farthest = pedestrian;
      }
    }
    farthest!
      ..position = door.clone()
      ..knockedDownSeconds = 0.0
      ..revive()
      ..scare(awayFrom, seconds: 8.0);
  }

  /// Ушедший за [despawnRadius] пешеход переселяется — в кольцо от
  /// [minRespawnDistance], чтобы не возникнуть перед носом у игрока.
  /// Камера здесь сознательно не участвует (существование агентов — только
  /// по расстоянию, см. PROGRESS.md).
  void _respawnNear(Pedestrian pedestrian, vm.Vector3 center) {
    pedestrian
      ..position = _randomSpotNear(center, minDistance: minRespawnDistance)
      ..knockedDownSeconds = 0.0
      ..panicSeconds = 0.0
      ..fleeFrom = null
      ..idleSeconds = 0.0
      ..revive();
  }

  /// Случайная точка в кольце [minDistance]..[spawnRadius], где можно стоять
  /// пешком и не на проезжей части. Если за разумное число попыток не
  /// нашлось — рядом с самим [center].
  vm.Vector3 _randomSpotNear(vm.Vector3 center, {double minDistance = 0.0}) {
    for (var attempt = 0; attempt < 60; attempt++) {
      final radius = minDistance + _random.nextDouble() * (spawnRadius - minDistance);
      final angle = _random.nextDouble() * 2 * math.pi;
      final x = center.x + math.sin(angle) * radius;
      final z = center.z + math.cos(angle) * radius;
      final kind = nav.kindAt(x, z);
      if (kind == NavKind.ground || kind == NavKind.sidewalk) return vm.Vector3(x, 0, z);
    }
    return vm.Vector3(center.x, 0, center.z);
  }
}
