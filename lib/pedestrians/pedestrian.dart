import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

/// Проверка клетки мира по координатам: можно ли туда (пешком / вообще).
/// В игре это NavGrid (lib/world/nav_grid.dart), в тестах — подставная.
typedef AreaTest = bool Function(double x, double z);

/// Чистое (без Flutter/flutter_scene) состояние одного NPC-пешехода —
/// отдельно от рендера (см. pedestrian_system.dart), чтобы логику можно
/// было проверить юнит-тестом без GPU.
///
/// Пешеход бродит хаотично по навигационной сетке района: курс время от
/// времени меняется случайно, перед каждым шагом путь щупается вперёд, и
/// в дом или на крупную дорогу пешеход не заходит — поворачивает. Раньше
/// он шёл по прямой между узлами дорожного графа, и эти прямые (тротуары,
/// дворовые проезды из OSM) резали углы домов — пешеходы ходили сквозь
/// стены (BUGS.md).
class Pedestrian {
  Pedestrian({required this.position, this.yaw = 0.0}) : desiredYaw = yaw;

  vm.Vector3 position;
  double yaw;

  /// Куда хочет идти — к нему поворачивает при первой возможности.
  double desiredYaw;

  /// Через сколько секунд сменить курс прогулки.
  double wanderSeconds = 0.0;

  /// Сколько ещё секунд стоит на месте (постоял, огляделся).
  double idleSeconds = 0.0;

  /// Индекс инстанса в общем InstancedMesh (см. PedestrianSystem) — не
  /// логика, просто чтобы рендеру было куда писать обновлённый transform.
  int instanceIndex = -1;

  /// Сколько ещё секунд лежит сбитый машиной (0 — на ногах).
  double knockedDownSeconds = 0.0;

  /// Скорость отлёта после удара, гасится трением (см. [advancePedestrian]).
  vm.Vector3 knockbackVelocity = vm.Vector3.zero();

  bool get isKnockedDown => knockedDownSeconds > 0.0;

  /// Здоровье 0..[maxHealth]. Пистолет (assets/data/weapons.json) снимает
  /// треть за выстрел в корпус.
  static const double maxHealth = 100.0;
  double health = maxHealth;

  /// Убит — лежит на месте, пока система не переселит его подальше от
  /// игрока (см. PedestrianSystem).
  bool isDead = false;

  /// Сколько секунд лежит мёртвым — тело убирается, только когда давно
  /// лежит и игрок далеко.
  double deadSeconds = 0.0;

  /// Можно ли попасть пулей: на ногах и жив. Лежачих пуля пока не
  /// задевает — капсула лежит, а проверка попадания под стоящую.
  bool get isShootable => !isDead && !isKnockedDown;

  /// Сколько ещё секунд бежит в панике — скорость в
  /// [panicSpeedMultiplier] раз выше шага.
  double panicSeconds = 0.0;

  /// От чего бежит в панике (стрелок, угонщик). null — паника без
  /// направления.
  vm.Vector3? fleeFrom;

  /// Пуля попала: урон [damage] со стороны [from]. Возвращает true, если
  /// это убило. Раненый в панике бежит прочь.
  bool takeDamage(double damage, vm.Vector3 from) {
    if (isDead) return false;
    health -= damage;
    if (health > 0.0) {
      scare(from);
      return false;
    }
    health = 0.0;
    isDead = true;
    deadSeconds = 0.0;
    panicSeconds = 0.0;
    fleeFrom = null;
    // Падает навзничь от стрелка, без отлёта.
    final away = vm.Vector3(position.x - from.x, 0, position.z - from.z);
    if (away.length2 > 1e-6) yaw = math.atan2(away.x, away.z);
    knockbackVelocity.setZero();
    return true;
  }

  /// Испугался (выстрел, угон) в [from]: бежит [seconds] секунд прочь.
  void scare(vm.Vector3 from, {double seconds = 10.0}) {
    if (isDead) return;
    panicSeconds = math.max(panicSeconds, seconds);
    fleeFrom = from.clone();
    idleSeconds = 0.0;
  }

  /// Вернуть к жизни при переселении (новый человек на месте старого).
  void revive() {
    health = maxHealth;
    isDead = false;
    deadSeconds = 0.0;
  }

  /// Удар машиной: отлетает от [impactFrom] (центр машины) со скоростью,
  /// растущей со скоростью машины [impactSpeed], и лежит [lieSeconds].
  void knockDown(vm.Vector3 impactFrom, double impactSpeed, {double lieSeconds = 6.0}) {
    knockedDownSeconds = lieSeconds;
    final away = vm.Vector3(position.x - impactFrom.x, 0, position.z - impactFrom.z);
    if (away.length2 < 1e-6) away.setValues(math.sin(yaw), 0, math.cos(yaw));
    away.normalize();
    knockbackVelocity = away * math.min(impactSpeed * 0.4, 6.0);
    yaw = math.atan2(away.x, away.z);
  }
}

/// Во сколько раз быстрее шага бежит перепуганный пешеход (1.3 -> ~4.5 м/с).
const double panicSpeedMultiplier = 3.5;

/// Трение скольжения сбитого пешехода по земле, 1/с: при отлёте 6 м/с
/// он проезжает около метра (6 / 6).
const double _knockbackFriction = 6.0;

/// Насколько вперёд щупать путь: с запасом на корпус, чтобы не тереться
/// о стену.
const double pedestrianLookAhead = 1.2;

/// Повороты от желаемого курса, которые пробуются по очереди, если прямо
/// нельзя: сначала чуть-чуть, потом круче, в конце — назад.
const List<double> _detours = [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.3, -2.3, math.pi];

/// Один кадр пешехода. [walkable] — можно ли туда пешком (земля, тротуар,
/// мелкая дорога), [solid] — нельзя вообще (дом). Пешеход никогда не
/// шагает в [solid] и, если стоит на проходимом, — не уходит на
/// непроходимое. Оказался вне проходимого (выпрыгнул из угнанной машины
/// на крупную дорогу, отлетел от удара) — выбирается любым путём не через
/// дома.
void advancePedestrian(
  Pedestrian pedestrian, {
  required AreaTest walkable,
  required AreaTest solid,
  required double dt,
  required double speed,
  required math.Random random,
}) {
  final p = pedestrian.position;
  if (pedestrian.isDead) {
    pedestrian.deadSeconds += dt;
    return;
  }

  if (pedestrian.isKnockedDown) {
    pedestrian.knockedDownSeconds = math.max(0.0, pedestrian.knockedDownSeconds - dt);
    final next = p + pedestrian.knockbackVelocity * dt;
    // В стену не влетает — останавливается о неё.
    if (solid(next.x, next.z)) {
      pedestrian.knockbackVelocity.setZero();
    } else {
      pedestrian.position = next;
    }
    pedestrian.knockbackVelocity.scale(math.exp(-_knockbackFriction * dt));
    return;
  }

  final fleeFrom = pedestrian.fleeFrom;
  if (pedestrian.panicSeconds > 0.0) {
    pedestrian.panicSeconds = math.max(0.0, pedestrian.panicSeconds - dt);
    speed *= panicSpeedMultiplier;
    if (pedestrian.panicSeconds == 0.0) pedestrian.fleeFrom = null;
  }

  if (fleeFrom != null && pedestrian.panicSeconds > 0.0) {
    // Прочь от угрозы.
    final dx = p.x - fleeFrom.x;
    final dz = p.z - fleeFrom.z;
    if (dx * dx + dz * dz > 1e-6) pedestrian.desiredYaw = math.atan2(dx, dz);
  } else {
    if (pedestrian.idleSeconds > 0.0) {
      pedestrian.idleSeconds -= dt;
      return;
    }
    pedestrian.wanderSeconds -= dt;
    if (pedestrian.wanderSeconds <= 0.0) {
      pedestrian.wanderSeconds = 2.0 + random.nextDouble() * 5.0;
      // Иногда постоять, обычно — свернуть в случайную сторону.
      if (random.nextDouble() < 0.15) {
        pedestrian.idleSeconds = 1.0 + random.nextDouble() * 2.5;
        return;
      }
      pedestrian.desiredYaw = pedestrian.yaw + (random.nextDouble() - 0.5) * math.pi * 0.9;
    }
  }

  final escaping = !walkable(p.x, p.z);
  bool canStand(double x, double z) => escaping ? !solid(x, z) : walkable(x, z);

  final step = speed * dt;
  for (final detour in _detours) {
    final angle = pedestrian.desiredYaw + detour;
    final sx = math.sin(angle);
    final sz = math.cos(angle);
    final aheadX = p.x + sx * pedestrianLookAhead;
    final aheadZ = p.z + sz * pedestrianLookAhead;
    final nextX = p.x + sx * step;
    final nextZ = p.z + sz * step;
    if (!canStand(aheadX, aheadZ) || !canStand(nextX, nextZ)) continue;
    pedestrian.position = vm.Vector3(nextX, p.y, nextZ);
    pedestrian.yaw = angle;
    // Свернул — теперь идёт туда, а не бьётся в ту же стену.
    if (detour != 0.0) pedestrian.desiredYaw = angle;
    return;
  }
  // Тупик со всех сторон — развернуться и попробовать в следующий кадр.
  pedestrian.desiredYaw += math.pi;
}
