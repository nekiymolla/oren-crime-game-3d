import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'package:crime_oren/player/character_controller_component.dart';
import 'package:crime_oren/player/character_motion.dart';

/// Вертикальная стена-плоскость x = [wallX] на участке z в [zMin, zMax]
/// (бесконечная по высоте — как выдавленные стены osm2world). Нормаль
/// смотрит к -X, то есть к персонажу, подходящему слева. Геометрию в тестах
/// создавать нельзя (нужен GPU), поэтому луч считается аналитически.
CharacterRaycaster wallAt(
  double wallX, {
  double zMin = -1e9,
  double zMax = 1e9,
}) {
  return (origin, direction, maxDistance) {
    if (direction.x <= 1e-9 || origin.x > wallX) return null;
    final t = (wallX - origin.x) / direction.x;
    if (t > maxDistance) return null;
    final z = origin.z + direction.z * t;
    if (z < zMin || z > zMax) return null;
    return CharacterRayHit(distance: t, normal: vm.Vector3(-1, 0, 0));
  };
}

/// Дом-коробка в плане: [minX..maxX] x [minZ..maxZ], бесконечная по высоте.
/// Луч снаружи — slab-тест, нормаль той грани, в которую вошёл луч.
CharacterRaycaster boxAt(double minX, double maxX, double minZ, double maxZ) {
  return (origin, direction, maxDistance) {
    var tEnter = -double.infinity;
    var tExit = double.infinity;
    vm.Vector3? normal;
    for (final axis in [0, 2]) {
      final o = origin[axis];
      final d = direction[axis];
      final lo = axis == 0 ? minX : minZ;
      final hi = axis == 0 ? maxX : maxZ;
      if (d.abs() < 1e-12) {
        if (o < lo || o > hi) return null;
        continue;
      }
      var t1 = (lo - o) / d;
      var t2 = (hi - o) / d;
      var sign = -1.0;
      if (t1 > t2) {
        final tmp = t1;
        t1 = t2;
        t2 = tmp;
        sign = 1.0;
      }
      if (t1 > tEnter) {
        tEnter = t1;
        normal = axis == 0 ? vm.Vector3(sign, 0, 0) : vm.Vector3(0, 0, sign);
      }
      tExit = math.min(tExit, t2);
    }
    if (tEnter < 0 || tEnter > tExit || tEnter > maxDistance) return null;
    return CharacterRayHit(distance: tEnter, normal: normal!);
  };
}

/// Расстояние в плане от точки до коробки (0 — внутри).
double distanceToBox(vm.Vector3 p, double minX, double maxX, double minZ, double maxZ) {
  final dx = math.max(0.0, math.max(minX - p.x, p.x - maxX));
  final dz = math.max(0.0, math.max(minZ - p.z, p.z - maxZ));
  return math.sqrt(dx * dx + dz * dz);
}

/// Прогон [seconds] секунд с шагом 60 Гц.
void run(CharacterMotion motion, double seconds) {
  const dt = 1 / 60;
  for (var i = 0; i < (seconds / dt).round(); i++) {
    motion.step(dt);
  }
}

void main() {
  test('без препятствий идёт вперёд со скоростью шага', () {
    final motion = CharacterMotion()..setMoveInput(vm.Vector2(0, 1));
    run(motion, 2.0);
    expect(motion.isGrounded, isTrue);
    expect(motion.position.y, closeTo(0.0, 1e-6));
    expect(motion.horizontalSpeed, closeTo(4.5, 0.05));
    expect(motion.position.z, greaterThan(8.0));
  });

  test('бег быстрее шага в runMultiplier раз', () {
    final motion = CharacterMotion()
      ..setMoveInput(vm.Vector2(0, 1), isRunning: true);
    run(motion, 2.0);
    expect(motion.horizontalSpeed, closeTo(4.5 * 1.8, 0.1));
  });

  test('упирается в стену и не проходит сквозь неё даже бегом', () {
    final motion = CharacterMotion(raycast: wallAt(3.0))
      ..setMoveInput(vm.Vector2(1, 0), isRunning: true);
    run(motion, 5.0);
    // Центр тела не ближе радиуса к стене (с запасом на шаг кадра).
    expect(motion.position.x, lessThan(3.0 - 0.45));
    expect(motion.horizontalSpeed, lessThan(0.5));
  });

  test('при движении по диагонали в стену скользит вдоль неё', () {
    final motion = CharacterMotion(raycast: wallAt(2.0))
      ..setMoveInput(vm.Vector2(1, 1));
    run(motion, 3.0);
    expect(motion.position.x, lessThan(2.0 - 0.45));
    // Вдоль стены движение продолжается, а не залипает.
    expect(motion.position.z, greaterThan(5.0));
  });

  test('в угол дома не заходит ни под каким углом подхода', () {
    // Дом 10x10 с углом в (0, 0); персонаж бежит в угол с разных сторон,
    // включая почти параллельно стене — именно так он раньше залезал
    // в здание наполовину (3 луча вдоль движения не видели стену сбоку).
    for (var deg = 0; deg < 360; deg += 10) {
      final a = deg * math.pi / 180;
      final start = vm.Vector3(-3 * math.cos(a), 0, -3 * math.sin(a));
      // Старт внутри дома или вплотную к нему — не подход снаружи.
      if (distanceToBox(start, 0, 10, 0, 10) < 1.0) continue;
      final motion = CharacterMotion(
        raycast: boxAt(0, 10, 0, 10),
        position: start,
      )..setMoveInput(vm.Vector2(-start.x, -start.z).normalized(), isRunning: true);
      for (var i = 0; i < 180; i++) {
        motion.step(1 / 60);
        // Капсула-плейсхолдер радиусом 0.4 не должна пересекать дом.
        expect(
          distanceToBox(motion.position, 0, 10, 0, 10),
          greaterThan(0.4),
          reason: 'подход под $deg°, кадр $i, pos=${motion.position}',
        );
      }
    }
  });

  test('огибает угол дома, скользя вдоль стены', () {
    // Идёт вдоль стены x = 0 почти параллельно ей и должен пройти дальше
    // угла, а не застрять на нём.
    final motion = CharacterMotion(
      raycast: boxAt(0, 10, 0, 10),
      position: vm.Vector3(-1, 0, 2),
    )..setMoveInput(vm.Vector2(0.15, -1).normalized());
    run(motion, 3.0);
    expect(motion.position.z, lessThan(-5.0));
  });

  test('камера развёрнута — "вперёд" на джойстике идёт от камеры', () {
    final motion = CharacterMotion()
      ..setMoveInput(vm.Vector2(0, 1), cameraHeadingYaw: math.pi / 2);
    run(motion, 1.0);
    expect(motion.position.x.abs(), greaterThan(2.0));
    expect(motion.position.z.abs(), lessThan(0.1));
  });

  test('прыжок отрывает от земли и возвращает обратно', () {
    final motion = CharacterMotion();
    run(motion, 0.5);
    motion.jump();
    var maxY = 0.0;
    for (var i = 0; i < 120; i++) {
      motion.step(1 / 60);
      maxY = math.max(maxY, motion.position.y);
    }
    // v²/2g = 36/36 = 1 м.
    expect(maxY, closeTo(1.0, 0.1));
    expect(motion.isGrounded, isTrue);
    expect(motion.position.y, closeTo(0.0, 1e-6));
  });

  test('застрявшего в стене выталкивает наружу, а не внутрь', () {
    // Тело уже почти в стене: до неё 0.1 м при радиусе 0.5.
    final motion = CharacterMotion(
      raycast: wallAt(0.1),
    )..setMoveInput(vm.Vector2(1, 0));
    run(motion, 1.0);
    expect(motion.position.x, lessThan(0.0));
  });

  test('радиус тела 0 выключает обход — проходит сквозь стену (замер)', () {
    final motion = CharacterMotion(raycast: wallAt(2.0), bodyRadius: 0.0)
      ..setMoveInput(vm.Vector2(1, 0));
    run(motion, 2.0);
    expect(motion.position.x, greaterThan(2.0));
  });

  test('компонент берёт спавн из узла и подхватывает телепорт', () {
    final node = Node()..position = vm.Vector3(10, 0, -5);
    final controller = CharacterControllerComponent();
    node.addComponent(controller);
    controller.fixedUpdate(1 / 60);
    expect(node.globalTransform.getTranslation().x, closeTo(10, 1e-4));

    // Внешний телепорт (арест / высадка из машины).
    node.position = vm.Vector3(-20, 0, 7);
    controller.setMoveInput(vm.Vector2(0, 1));
    for (var i = 0; i < 60; i++) {
      controller.fixedUpdate(1 / 60);
    }
    final p = node.globalTransform.getTranslation();
    expect(p.x, closeTo(-20, 0.01));
    expect(p.z, greaterThan(9.0));
  });
}
