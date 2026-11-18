import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

/// Попадание луча в том минимальном виде, который нужен движению персонажа:
/// дистанция вдоль луча и мировая нормаль поверхности (единичная, развёрнутая
/// к началу луча — ровно так её отдаёт `raycastNode`, см. SceneRaycastHit).
class CharacterRayHit {
  const CharacterRayHit({required this.distance, required this.normal});

  final double distance;
  final vm.Vector3 normal;
}

/// Луч против коллизионной геометрии мира. Отдельный тип, а не прямой вызов
/// `raycastNode`, по двум причинам:
///
/// 1. **Тестируемость.** Геометрию (`CuboidGeometry` и т.п.) в юнит-тестах
///    создавать нельзя — она требует живого Impeller-контекста, которого в
///    `flutter test` нет (см. PROGRESS.md, "Важный урок по тестированию").
///    Функцию-заглушку — можно, поэтому вся логика движения проверяется
///    headless, включая столкновения и скольжение вдоль стен.
/// 2. **Область обхода задаётся снаружи** (см. CharacterCollisionField) —
///    именно на ней и экономится кадр по сравнению со встроенным
///    `ThirdPersonControllerComponent`: тот всегда поднимается до корня сцены
///    (`_rootNode`) и сузить область не даёт, только `groundLayerMask`.
typedef CharacterRaycaster =
    CharacterRayHit? Function(
      vm.Vector3 origin,
      vm.Vector3 direction,
      double maxDistance,
    );

/// Кинематическое движение персонажа: ходьба/бег camera-relative, прыжок,
/// гравитация, следование за высотой земли, скольжение вдоль стен.
/// Чистая логика без flutter_scene — узел двигает обёртка
/// (см. CharacterControllerComponent), а здесь только математика и рейкасты
/// через подменяемый [raycast].
///
/// Написана вместо встроенного `ThirdPersonControllerComponent`, потому что
/// тот кидал **9 лучей обхода препятствий + 1 на землю каждый кадр по всему
/// графу сцены** — на слабом Android это 14 мс из 16.6 мс бюджета кадра
/// (замеры в PROGRESS.md). Здесь лучей 8 + 1, но каждый идёт по узкому
/// поддереву — одному-двум ближним чанкам (см. [raycast]), а дорог был
/// именно обход всего графа, а не число лучей.
///
/// **Прореживать проверки по кадрам нельзя** — уже пробовали и откатили:
/// встроенный контроллер не выталкивал из геометрии, а предотвращал вход,
/// так что пропущенный кадр оставлял игрока внутри стены (PROGRESS.md,
/// этап 3). Здесь выталкивание есть (см. [depenetrationSpeed]), но проверки
/// всё равно идут каждый кадр, пока персонаж движется.
class CharacterMotion {
  CharacterMotion({
    this.walkSpeed = 1.65,
    this.runMultiplier = 3.3,
    this.turnSpeed = 12.0,
    this.jumpVelocity = 6.0,
    this.gravity = 18.0,
    this.maxSlopeAngleDegrees = 45.0,
    this.coyoteTimeWindow = 0.12,
    this.jumpBufferWindow = 0.15,
    this.landingJumpDelay = 0.20,
    this.groundPlaneHeight = 0.0,
    this.groundHeightAt,
    this.bodyRadius = 0.5,
    this.chestHeight = 0.9,
    this.groundProbeHeight = 0.4,
    this.groundProbeDistance = 0.8,
    this.groundSnapDistance = 0.7,
    this.depenetrationSpeed = 1.5,
    this.raycast,
    vm.Vector3? position,
    double yaw = 0.0,
  }) : position = position ?? vm.Vector3.zero(),
       _yaw = yaw;

  /// Базовая скорость шага, м/с, и множитель бега.
  double walkSpeed;
  double runMultiplier;

  /// Скорость доворота персонажа к направлению движения, рад/с.
  double turnSpeed;

  /// Импульс прыжка вверх, м/с, и ускорение свободного падения, м/с².
  double jumpVelocity;
  double gravity;

  /// Круче этого угла поверхность считается склоном, по которому съезжают,
  /// а не стоят (градусы).
  double maxSlopeAngleDegrees;

  /// Прыжок разрешён ещё столько секунд после того, как земля кончилась
  /// (coyote time), и запоминается за столько секунд до касания земли
  /// (jump buffer). После приземления — пауза [landingJumpDelay].
  double coyoteTimeWindow;
  double jumpBufferWindow;
  double landingJumpDelay;

  /// Бесконечный плоский пол-заглушка: подхватывает персонажа там, где под
  /// ним нет геометрии района (плейсхолдер-земля в terrain.dart лежит чуть
  /// ниже нуля и в коллизионную область сознательно не входит — два
  /// треугольника на весь район незачем перебирать рейкастом).
  double? groundPlaneHeight;
  double Function(double x, double z)? groundHeightAt;

  /// Радиус тела для обхода препятствий (0 — обход выключен, только замер:
  /// без него игрок проходит сквозь стены) и высота, с которой щупаются
  /// препятствия — "грудь". См. [_probeObstacles] про выбор конфигурации.
  double bodyRadius;
  double chestHeight;

  /// Луч на землю: стартует на [groundProbeHeight] выше ног, летит вниз на
  /// [groundProbeDistance]; земля считается найденной, если попадание ближе
  /// [groundSnapDistance]. Разница между двумя последними — тот самый
  /// авто-шаг: бордюр/ступенька ниже [groundProbeHeight] просто
  /// подхватывается снизу, отдельных лучей на это не нужно.
  double groundProbeHeight;
  double groundProbeDistance;
  double groundSnapDistance;

  /// Выталкивание: если стена уже ближе [bodyRadius] (чанк догрузился
  /// вокруг персонажа, его телепортировали к дому), смещение получает
  /// добавку наружу вдоль нормали — не быстрее этого, м/с, чтобы не было
  /// рывка. Только наружу, так что протолкнуть себя сквозь стену этим нельзя.
  double depenetrationSpeed;

  /// Луч против коллизионной геометрии. null — мир без препятствий (движение
  /// считается по плоскому полу [groundPlaneHeight]); используется в тестах
  /// и как безопасный режим, пока мир не загружен.
  CharacterRaycaster? raycast;

  /// Мировая позиция точки контакта с землёй (низ капсулы).
  vm.Vector3 position;

  /// Текущая скорость, мировые координаты.
  vm.Vector3 velocity = vm.Vector3.zero();

  /// Стоит ли персонаж на земле и нормаль поверхности под ним.
  bool isGrounded = false;
  vm.Vector3 groundNormal = vm.Vector3(0, 1, 0);

  double _yaw;
  vm.Vector2 _moveInput = vm.Vector2.zero();
  bool _isRunning = false;
  double? _cameraHeadingYaw;
  double _coyoteTimer = 0.0;
  double _jumpBufferTimer = 0.0;
  double _landingTimer = 0.0;
  double _airborneTime = 0.0;

  /// Курс персонажа (рад), та же конвенция yaw, что у FollowCameraController.
  double get yaw => _yaw;

  /// Куда смотреть независимо от движения (прицеливание: корпус к
  /// прицелу, ходьба вбок/назад — стрейф). null — корпус по движению.
  double? facingYawOverride;

  /// Горизонтальная скорость, м/с — для HUD/анимаций.
  double get horizontalSpeed =>
      math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z);

  /// Ввод движения: [input] в диапазоне -1..1 по каждой оси (+Y — "вперёд"),
  /// [cameraHeadingYaw] — курс камеры, чтобы "вперёд" было "от камеры", а не
  /// "куда смотрит персонаж" (иначе после разворота камеры джойстик вёл бы в
  /// неожиданную сторону, см. PlayerInputBridgeComponent).
  void setMoveInput(
    vm.Vector2 input, {
    bool isRunning = false,
    double? cameraHeadingYaw,
  }) {
    _moveInput = input;
    _isRunning = isRunning;
    _cameraHeadingYaw = cameraHeadingYaw;
  }

  /// Запрос прыжка. Запоминается на [jumpBufferWindow] секунд, чтобы нажатие
  /// чуть раньше касания земли не пропадало.
  void jump() {
    _jumpBufferTimer = jumpBufferWindow;
  }

  /// Переставить персонажа (спавн, арест, высадка из машины) — сбрасывает
  /// скорость, иначе накопленное падение продолжится с новой точки.
  void teleport(vm.Vector3 newPosition, {double? yaw}) {
    position = newPosition.clone();
    velocity.setZero();
    isGrounded = false;
    _airborneTime = 0.0;
    if (yaw != null) _yaw = yaw;
  }

  /// Один шаг симуляции. Порядок тот же, что у встроенного контроллера, —
  /// так его поведение проще сверять глазами: земля, склон, прыжок,
  /// горизонтальная скорость, обход препятствий, применение смещения.
  void step(double dt) {
    if (dt <= 0.0) return;

    if (_coyoteTimer > 0.0) _coyoteTimer -= dt;
    if (_jumpBufferTimer > 0.0) _jumpBufferTimer -= dt;
    if (_landingTimer > 0.0) _landingTimer -= dt;

    // 1. Земля — единственный вертикальный луч (как и у встроенного).
    final groundY = _probeGround(dt);

    // 2. Склон круче maxSlopeAngleDegrees — стоять нельзя, съезжаем.
    final slopeAngle =
        math.acos(groundNormal.y.clamp(-1.0, 1.0)) * 180.0 / math.pi;
    final isTooSteep = slopeAngle > maxSlopeAngleDegrees;

    // 3. Прыжок / гравитация.
    if (_jumpBufferTimer > 0.0 &&
        (isGrounded || _coyoteTimer > 0.0) &&
        _landingTimer <= 0.0 &&
        !isTooSteep) {
      velocity.y = jumpVelocity;
      isGrounded = false;
      _coyoteTimer = 0.0;
      _jumpBufferTimer = 0.0;
    } else if (!isGrounded) {
      velocity.y -= gravity * dt;
    }

    // 4. Горизонтальная скорость по вводу (экспоненциальное сглаживание —
    // мгновенная смена скорости ощущается как телепорт).
    _integrateHorizontal(dt, isTooSteep: isTooSteep);
    final facing = facingYawOverride;
    if (facing != null) {
      // Быстрее обычного доворота: выстрел идёт сразу, корпус не должен
      // заметно отставать от прицела.
      final angleDiff = (facing - _yaw + math.pi) % (2 * math.pi) - math.pi;
      _yaw += angleDiff * (1.0 - math.exp(-turnSpeed * 2.5 * dt));
    }

    // 5. Обход препятствий — кольцо лучей вокруг тела.
    var move = vm.Vector3(velocity.x, 0.0, velocity.z) * dt;
    move = _probeObstacles(move, dt);

    // 6. Применяем смещение.
    position.x += move.x;
    position.z += move.z;
    if (isGrounded) {
      position.y = groundY;
    } else {
      position.y += velocity.y * dt;
    }
  }

  /// Вертикальный луч под ноги. Возвращает высоту земли (осмысленна только
  /// при [isGrounded]) и обновляет [isGrounded]/[groundNormal].
  double _probeGround(double dt) {
    var detected = false;
    var groundY = position.y;
    var normal = vm.Vector3(0, 1, 0);

    final rayStart = vm.Vector3(
      position.x,
      position.y + groundProbeHeight,
      position.z,
    );
    final hit = raycast?.call(
      rayStart,
      vm.Vector3(0, -1, 0),
      groundProbeDistance,
    );
    final terrainY =
        groundHeightAt?.call(position.x, position.z) ?? groundPlaneHeight;
    if (hit != null &&
        hit.distance <= groundSnapDistance &&
        (terrainY == null || rayStart.y - hit.distance >= terrainY - 0.05)) {
      detected = true;
      groundY = rayStart.y - hit.distance;
      normal = hit.normal;
    } else if (terrainY != null && position.y <= terrainY + 0.05) {
      detected = true;
      groundY = terrainY;
      final height = groundHeightAt;
      if (height != null) {
        const e = 0.1;
        normal = vm.Vector3(
          height(position.x - e, position.z) -
              height(position.x + e, position.z),
          2 * e,
          height(position.x, position.z - e) -
              height(position.x, position.z + e),
        ).normalized();
      }
    }

    if (detected &&
        velocity.y <= 0.0 &&
        (isGrounded || position.y <= groundY + 0.25)) {
      if (!isGrounded) {
        velocity.y = 0.0;
        if (_airborneTime > 0.08) _landingTimer = landingJumpDelay;
        _airborneTime = 0.0;
      }
      isGrounded = true;
      _coyoteTimer = coyoteTimeWindow;
      groundNormal = normal;
    } else {
      isGrounded = false;
      _airborneTime += dt;
    }
    return groundY;
  }

  void _integrateHorizontal(double dt, {required bool isTooSteep}) {
    final inputLength = _moveInput.length;
    if (inputLength > 0.01) {
      var inputX = _moveInput.x;
      var inputZ = _moveInput.y;
      final headingYaw = _cameraHeadingYaw;
      if (headingYaw != null) {
        final sinY = math.sin(headingYaw);
        final cosY = math.cos(headingYaw);
        final rotatedX = inputX * cosY + inputZ * sinY;
        final rotatedZ = -inputX * sinY + inputZ * cosY;
        inputX = rotatedX;
        inputZ = rotatedZ;
      }
      final targetSpeed = walkSpeed * (_isRunning ? runMultiplier : 1.0);
      // Preserve the stick's magnitude: a small deflection means a slow
      // step, while diagonal keyboard input must never exceed full speed.
      final desired =
          vm.Vector2(inputX, inputZ).normalized() *
          targetSpeed *
          inputLength.clamp(0.0, 1.0);

      final accelRate = isGrounded ? 15.0 : 4.0;
      final t = 1.0 - math.exp(-accelRate * dt);
      velocity.x += (desired.x - velocity.x) * t;
      velocity.z += (desired.y - velocity.z) * t;

      // Доворот корпуса к направлению движения по кратчайшей дуге (оператор %
      // для double в Dart всегда неотрицателен, поэтому разница попадает
      // ровно в [-pi, pi)).
      // При прицеливании корпус держит прицел (см. facingYawOverride).
      if (facingYawOverride == null) {
        final targetYaw = math.atan2(desired.x, desired.y);
        final angleDiff =
            (targetYaw - _yaw + math.pi) % (2 * math.pi) - math.pi;
        _yaw += angleDiff * (1.0 - math.exp(-turnSpeed * dt));
      }
    } else {
      final friction = isGrounded ? 12.0 : 2.0;
      final t = 1.0 - math.exp(-friction * dt);
      velocity.x += (0.0 - velocity.x) * t;
      velocity.z += (0.0 - velocity.z) * t;
    }

    if (isGrounded && isTooSteep) {
      final slideDir = vm.Vector3(
        groundNormal.x,
        0,
        groundNormal.z,
      ).normalized();
      velocity.x += slideDir.x * gravity * dt;
      velocity.z += slideDir.z * gravity * dt;
    }
  }

  /// Направления кольца лучей обхода — 8 штук через 45°, горизонтальные.
  static final List<vm.Vector3> _ringDirections = [
    for (var i = 0; i < 8; i++)
      vm.Vector3(math.sin(i * math.pi / 4), 0.0, math.cos(i * math.pi / 4)),
  ];

  /// Обход препятствий: тело — вертикальный цилиндр радиуса [bodyRadius],
  /// и из его центра на высоте груди во все стороны кольцом летят 8 лучей.
  /// Каждое попадание — плоскость стены, к которой центру нельзя подойти
  /// ближе радиуса: составляющая смещения "в стену" срезается ровно до
  /// оставшегося зазора, вдоль стены движение сохраняется (скольжение).
  ///
  /// Почему кольцо, а не лучи вдоль направления движения (так было в первой
  /// версии — 3 параллельных луча, центр + два "плеча"): при движении почти
  /// параллельно стене луч вдоль движения встречает её только на расстоянии
  /// d/sin(угла), то есть когда тело УЖЕ в стене. У угла дома так и
  /// выходило — персонаж заходил в здание наполовину (проверено вживую
  /// 14.10.2026). Кольцо меряет расстояние до стены в любой стороне, и щель
  /// между соседними лучами на угол здания — радиус * (1 - cos 22.5°),
  /// около 4 см при радиусе 0.5.
  ///
  /// Высоты (ноги/пояс/плечи) не нужны: стены районной геометрии —
  /// выдавленные из footprint'ов вертикали (osm2world), а низкие препятствия
  /// (бордюр, ступенька) не блокируются, а подхватываются лучом на землю
  /// (авто-шаг, см. [groundProbeHeight]).
  ///
  /// Повторные попадания в ту же стену соседними лучами безвредны:
  /// после первой поправки ограничение уже выполнено, вторая ничего не
  /// меняет. Во внутреннем углу две стены срезают каждая своё.
  vm.Vector3 _probeObstacles(vm.Vector3 move, double dt) {
    final caster = raycast;
    // Стоя на месте кольцо не кидается: стены не двигаются, а 8 лучей на
    // кадр впустую — ровно та цена, от которой мы уходили.
    if (caster == null || bodyRadius <= 0.0 || move.length2 <= 1e-8) {
      return move;
    }

    final moveLength = move.length;
    final origin = vm.Vector3(position.x, position.y + chestHeight, position.z);
    // Луч, пришедший в стену под углом, проходит до неё длиннее
    // перпендикуляра (d / cos угла): ближайший к нормали луч кольца бывает
    // до 22.5° от неё, а у угла дома он может пройти мимо грани, и стену
    // видит только сосед под 45°+. Отсюда запас в 1.5 раза — ограничение всё
    // равно считается по перпендикуляру, лишних блокировок длина не даёт.
    final maxProbeDistance = (bodyRadius + moveLength) * 1.5 + 0.05;
    final result = move.clone();

    for (final direction in _ringDirections) {
      final hit = caster(origin, direction, maxProbeDistance);
      if (hit == null) continue;

      // Стена интересует только горизонтальной частью нормали: вертикальная
      // (пол под наклоном, потолок) не должна ни тормозить, ни подбрасывать.
      final normal = vm.Vector3(hit.normal.x, 0.0, hit.normal.z);
      final normalLength = normal.length;
      if (normalLength < 1e-4) continue;
      normal.scale(1.0 / normalLength);

      // Расстояние от центра до плоскости стены (перпендикуляр), а не до
      // точки попадания вдоль луча.
      final facing = -direction.dot(normal);
      if (facing <= 1e-3) continue;
      final room = hit.distance * facing - bodyRadius;

      // Минимально допустимое смещение вдоль нормали: при запасе — "не
      // ближе стены на room", при проникновении — наружу, но не быстрее
      // depenetrationSpeed.
      final minAlong = room >= 0.0
          ? -room
          : math.min(-room, depenetrationSpeed * dt);
      final along = result.dot(normal);
      if (along < minAlong) {
        result.addScaled(normal, minAlong - along);
        // Гасим и скорость "в стену", иначе в следующем кадре она снова
        // считалась бы полной и персонаж дёргался бы на стене.
        final velocityAlong = velocity.x * normal.x + velocity.z * normal.z;
        if (velocityAlong < 0.0) {
          velocity.x -= normal.x * velocityAlong;
          velocity.z -= normal.z * velocityAlong;
        }
      }
    }
    return result;
  }
}
