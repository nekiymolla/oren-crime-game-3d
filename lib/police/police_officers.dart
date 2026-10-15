import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../characters/character_animation.dart';
import '../characters/character_library.dart';
import '../characters/character_model.dart';
import '../weapons/ballistics.dart';
import '../weapons/player_shooting.dart';
import 'police_officer.dart';

/// Выстрел офицера по игроку — для эффектов и урона (см. Game).
class OfficerShot {
  const OfficerShot({required this.muzzle, required this.end, required this.hit});

  final vm.Vector3 muzzle;
  final vm.Vector3 end;
  final bool hit;
}

/// Полицейские пешком: выходят из патрульных машин (PoliceSystem.deploy),
/// идут к игроку при прямой видимости и стреляют. В них можно попасть —
/// это цели для пуль игрока, как пешеходы ([ShootTargets]).
///
/// Рендер — фиксированный пул из [poolSize] мест: анимированные модели из
/// [characters] (свободные спрятаны), без библиотеки (тесты) — тёмно-синие
/// капсулы одним InstancedMesh. На развёртывание ничего не создаётся.
class PoliceOfficers implements ShootTargets {
  PoliceOfficers({math.Random? random, CharacterLibrary? characters})
    : _random = random ?? math.Random(),
      bodies = InstancedMesh(
        geometry: CapsuleGeometry(radius: _radius, height: _bodyHeight),
        material: PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(1, 1, 1, 1)
          ..roughnessFactor = 0.7,
      ) {
    for (var i = 0; i < poolSize; i++) {
      if (characters == null) {
        bodies.addInstance(_hidden, color: vm.Vector4(0.08, 0.12, 0.32, 1.0));
      } else {
        final model = characters.createOfficer(_random)..visible = false;
        _models.add(model);
        _root.add(model.node);
      }
    }
  }

  /// Модели мест пула (пусто без библиотеки персонажей).
  final List<CharacterModel> _models = [];
  final List<vm.Vector3> _lastPositions = List.generate(poolSize, (_) => vm.Vector3.zero());
  final Node _root = Node();

  static const int poolSize = 6;
  static const int officersPerCar = 2;

  /// Тот же размер, что у пешеходов.
  static const double _radius = 0.3;
  static const double _bodyHeight = 0.9;
  static const double _totalHeight = _bodyHeight + _radius * 2;

  /// Убитый офицер исчезает, когда давно лежит и игрок далеко.
  static const double _bodyCleanupSeconds = 45.0;
  static const double _bodyCleanupDistance = 60.0;

  static final vm.Matrix4 _hidden = vm.Matrix4.compose(vm.Vector3(0, -50, 0), vm.Quaternion.identity(), vm.Vector3.all(0.01));

  final math.Random _random;
  final InstancedMesh bodies;
  final List<PoliceOfficer?> _slots = List.filled(poolSize, null);

  Node buildNode() {
    if (_models.isEmpty) _root.addComponent(InstancedMeshComponent(bodies));
    return _root;
  }

  Iterable<PoliceOfficer> get _active => _slots.whereType<PoliceOfficer>();

  /// Живые офицеры машины [unitId].
  int aliveCount(int unitId) => _active.where((o) => o.unitId == unitId && !o.isDead).length;

  /// Офицеры машины [unitId] потеряли игрока: никто из живых не видел его
  /// дольше [seconds].
  bool lostSight(int unitId, double seconds) {
    final alive = _active.where((o) => o.unitId == unitId && !o.isDead);
    return alive.isNotEmpty && alive.every((o) => o.secondsWithoutSight >= seconds);
  }

  /// Положения живых — препятствия для трафика.
  Iterable<vm.Vector3> get alivePositions => _active.where((o) => !o.isDead).map((o) => o.position);

  /// Высадить офицеров из машины в [carPosition] с курсом [carHeading]:
  /// по одному с каждой стороны. Возвращает, сколько вышло (пул может
  /// быть занят телами).
  int deploy(int unitId, vm.Vector3 carPosition, double carHeading) {
    final right = vm.Vector3(math.cos(carHeading), 0, -math.sin(carHeading));
    var deployed = 0;
    for (final side in [-1.0, 1.0]) {
      final slot = _freeSlot();
      if (slot == null) break;
      final officer = PoliceOfficer(position: carPosition + right * (1.6 * side), unitId: unitId, yaw: carHeading);
      _slots[slot] = officer;
      _lastPositions[slot].setFrom(officer.position);
      _show(slot, officer);
      deployed++;
    }
    return deployed;
  }

  /// Живые офицеры машины садятся обратно (исчезают); тела остаются.
  void recall(int unitId) {
    for (var i = 0; i < poolSize; i++) {
      final officer = _slots[i];
      if (officer != null && officer.unitId == unitId && !officer.isDead) _free(i);
    }
  }

  /// Убрать всех, включая тела (арест, смерть игрока).
  void clear() {
    for (var i = 0; i < poolSize; i++) {
      if (_slots[i] != null) _free(i);
    }
  }

  /// Кадр всех офицеров. [lineOfSight] — луч от глаз офицера к игроку
  /// свободен. Возвращает выстрелы этого кадра.
  List<OfficerShot> update(
    double dt,
    vm.Vector3 player, {
    required double playerSpeed,
    required bool playerInVehicle,
    required bool Function(vm.Vector3 from, vm.Vector3 to) lineOfSight,
    OfficerPathProbe? pathClear,
  }) {
    final shots = <OfficerShot>[];
    final chest = player + vm.Vector3(0, playerInVehicle ? 1.0 : 1.1, 0);
    for (var i = 0; i < poolSize; i++) {
      final officer = _slots[i];
      if (officer == null) continue;
      if (officer.isDead) {
        officer.deadSeconds += dt;
        if (officer.deadSeconds > _bodyCleanupSeconds && (officer.position - player).length > _bodyCleanupDistance) {
          _free(i);
        } else if (_models.isNotEmpty) {
          _animate(i, officer, dt, sees: false, fired: false);
        }
        continue;
      }
      final eye = officer.position + vm.Vector3(0, 1.4, 0);
      final sees = lineOfSight(eye, chest);
      final fires = stepOfficer(officer, player, dt, hasLineOfSight: sees, random: _random, pathClear: pathClear);
      if (_models.isEmpty) {
        bodies.setInstanceTransform(i, _transform(officer));
      } else {
        _animate(i, officer, dt, sees: sees, fired: fires);
      }
      if (!fires) continue;

      final muzzle = officer.position + vm.Vector3(0, 1.3, 0) + vm.Vector3(math.sin(officer.yaw), 0, math.cos(officer.yaw)) * 0.45;
      final distance = (chest - muzzle).length;
      final hit = _random.nextDouble() < officerHitChance(distance, targetSpeed: playerSpeed, targetInVehicle: playerInVehicle);
      // Промах — пуля проходит рядом и улетает дальше.
      final end = hit
          ? chest
          : chest + (chest - muzzle).normalized() * 6.0 + vm.Vector3((_random.nextDouble() - 0.5) * 2.5, _random.nextDouble() * 1.2, (_random.nextDouble() - 0.5) * 2.5);
      shots.add(OfficerShot(muzzle: muzzle, end: end, hit: hit));
    }
    return shots;
  }

  @override
  ({int index, double distance, BodyZone zone})? raycastShootable(vm.Vector3 origin, vm.Vector3 direction, double maxDistance) {
    ({int index, double distance, BodyZone zone})? best;
    for (var i = 0; i < poolSize; i++) {
      final officer = _slots[i];
      if (officer == null || !officer.isShootable) continue;
      final t = rayVerticalCapsule(origin, direction, best?.distance ?? maxDistance, officer.position, _radius, _totalHeight);
      if (t == null) continue;
      final hitY = origin.y + direction.y * t;
      best = (index: i, distance: t, zone: zoneForHitHeight(hitY - officer.position.y, _totalHeight));
    }
    return best;
  }

  @override
  bool applyShot(int index, double damage, vm.Vector3 from) {
    final officer = _slots[index];
    if (officer == null) return false;
    final killed = officer.takeDamage(damage, from);
    if (_models.isEmpty) {
      bodies.setInstanceTransform(index, _transform(officer));
    } else if (!killed) {
      _models[index].play(CharacterAnim.hit, fadeSeconds: 0.08, restart: true);
    }
    return killed;
  }

  @override
  void collectAimPoints(List<vm.Vector3> points, List<int> indices) {
    for (var i = 0; i < poolSize; i++) {
      final officer = _slots[i];
      if (officer == null || !officer.isShootable) continue;
      points.add(officer.position + vm.Vector3(0, _totalHeight * 0.65, 0));
      indices.add(i);
    }
  }

  @override
  vm.Vector3 feetOf(int index) => _slots[index]?.position.clone() ?? vm.Vector3.zero();

  @override
  TargetKind kindOf(int index) => TargetKind.officer;

  /// Офицеры не разбегаются, но стрельба при них — всегда при свидетелях.
  @override
  int scareAround(vm.Vector3 shooter, double radius) =>
      _active.where((o) => !o.isDead && (o.position - shooter).length <= radius).length;

  int? _freeSlot() {
    for (var i = 0; i < poolSize; i++) {
      if (_slots[i] == null) return i;
    }
    return null;
  }

  void _free(int slot) {
    _slots[slot] = null;
    if (_models.isEmpty) {
      bodies.setInstanceTransform(slot, _hidden);
    } else {
      _models[slot].visible = false;
    }
  }

  void _show(int slot, PoliceOfficer officer) {
    if (_models.isEmpty) {
      bodies.setInstanceTransform(slot, _transform(officer));
      return;
    }
    final model = _models[slot]
      ..visible = true
      ..play(CharacterAnim.run, fadeSeconds: 0);
    model.node.position = officer.position;
    model.node.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), officer.yaw);
  }

  /// Клип офицера: убит — лежит, бежит — бег, стоит и видит игрока —
  /// целится (выстрел — отдача), иначе стоит.
  void _animate(int slot, PoliceOfficer officer, double dt, {required bool sees, required bool fired}) {
    final model = _models[slot];
    final last = _lastPositions[slot];
    final dx = officer.position.x - last.x;
    final dz = officer.position.z - last.z;
    last.setFrom(officer.position);
    model.node.position = officer.position;
    model.node.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), officer.yaw);
    final speed = officer.isDead || dt <= 0 ? 0.0 : math.sqrt(dx * dx + dz * dz) / dt;
    final reacting = (model.current == CharacterAnim.hit || model.current == CharacterAnim.shoot) &&
        !model.currentFinished &&
        !officer.isDead;
    if (fired && speed < 0.5) {
      model.play(CharacterAnim.shoot, fadeSeconds: 0.05, restart: true);
    } else if (!reacting) {
      final choice = locomotionAnim(speed: speed, lying: officer.isDead, aiming: sees);
      model.play(choice.anim, rate: choice.rate, fadeSeconds: officer.isDead ? 0.12 : 0.2);
    }
    model.update(dt);
  }

  vm.Matrix4 _transform(PoliceOfficer officer) {
    final heading = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), officer.yaw);
    if (!officer.isDead) {
      return vm.Matrix4.compose(officer.position + vm.Vector3(0, _totalHeight / 2, 0), heading, vm.Vector3.all(1.0));
    }
    return vm.Matrix4.compose(
      officer.position + vm.Vector3(0, _radius, 0),
      heading * vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
      vm.Vector3.all(1.0),
    );
  }
}
