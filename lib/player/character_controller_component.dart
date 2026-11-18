import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'character_motion.dart';

/// Обёртка [CharacterMotion] в компонент узла — заменяет встроенный
/// `ThirdPersonControllerComponent`. Интерфейс совместим намеренно
/// (`setMoveInput`, `jump`, `velocity`, `isGrounded`), чтобы остальной код
/// (PlayerInputBridgeComponent, Game) не переписывать.
///
/// Сама обёртка тонкая: читает/пишет трансформ узла, а всё движение и лучи —
/// в [motion], которая ничего не знает про flutter_scene и потому проверяется
/// юнит-тестами headless (геометрию в тестах создавать нельзя, см.
/// PROGRESS.md).
class CharacterControllerComponent extends Component {
  CharacterControllerComponent({
    double walkSpeed = 1.65,
    double runMultiplier = 3.3,
    double turnSpeed = 12.0,
    double jumpVelocity = 6.0,
    double gravity = 18.0,
    double? groundPlaneHeight = 0.0,
    double Function(double, double)? groundHeightAt,
    double bodyRadius = 0.5,
    double chestHeight = 0.9,
    double yaw = 0.0,
    CharacterRaycaster? raycast,
  }) : motion = CharacterMotion(
         walkSpeed: walkSpeed,
         runMultiplier: runMultiplier,
         turnSpeed: turnSpeed,
         jumpVelocity: jumpVelocity,
         gravity: gravity,
         groundPlaneHeight: groundPlaneHeight,
         groundHeightAt: groundHeightAt,
         bodyRadius: bodyRadius,
         chestHeight: chestHeight,
         yaw: yaw,
         raycast: raycast,
       );

  final CharacterMotion motion;

  /// Первый кадр ещё не считался — позицию нужно взять из узла (её ставит
  /// Game.load() по точке спавна), а не наоборот.
  bool _initialized = false;

  /// Насколько позиция узла должна разойтись с нашей, чтобы считать это
  /// внешним перемещением (телепорт при аресте, высадка из машины), а не
  /// погрешностью обратного чтения трансформа. Сантиметр: все реальные
  /// телепорты в игре — метры, а порог заведомо больше любой погрешности
  /// round-trip через матрицу родителя.
  static const double _externalMoveEpsilon = 0.01;

  // --- Интерфейс, совместимый со встроенным контроллером ---

  void setMoveInput(
    vm.Vector2 input, {
    bool isRunning = false,
    double? cameraHeadingYaw,
  }) => motion.setMoveInput(
    input,
    isRunning: isRunning,
    cameraHeadingYaw: cameraHeadingYaw,
  );

  void jump() => motion.jump();

  /// См. CharacterMotion.facingYawOverride.
  set facingYawOverride(double? yaw) => motion.facingYawOverride = yaw;

  vm.Vector3 get velocity => motion.velocity;
  double get horizontalSpeed => motion.horizontalSpeed;
  bool get isGrounded => motion.isGrounded;

  /// 0 выключает обход препятствий (только для замеров — без него игрок
  /// проходит сквозь стены, см. Game.obstacleAvoidance).
  double get bodyRadius => motion.bodyRadius;
  set bodyRadius(double value) => motion.bodyRadius = value;

  /// Луч против коллизионной геометрии. Ставится после сборки мира: узел
  /// игрока создаётся раньше, чем область коллизий (см. Game.load()).
  CharacterRaycaster? get raycast => motion.raycast;
  set raycast(CharacterRaycaster? value) => motion.raycast = value;

  /// Переставить персонажа явно. Внешнюю смену `node.position` компонент
  /// подхватывает и сам (см. [_syncFromNode]), но телепорт через этот метод
  /// заодно сбрасывает скорость и может задать курс.
  void teleport(vm.Vector3 position, {double? yaw}) {
    motion.teleport(position, yaw: yaw);
    if (isAttached) _writeToNode();
  }

  @override
  void update(double deltaSeconds) => fixedUpdate(deltaSeconds);

  @override
  void fixedUpdate(double fixedDt) {
    if (fixedDt <= 0.0 || !isAttached) return;
    _syncFromNode();
    motion.step(fixedDt);
    _writeToNode();
  }

  /// Позицию (и на первом кадре курс) берём из узла: так работают спавн в
  /// Game.load() и телепорты (`playerNode.position = ...` при аресте и при
  /// высадке из машины) без отдельного вызова [teleport].
  void _syncFromNode() {
    final nodePosition = node.globalTransform.getTranslation();
    if (!_initialized) {
      _initialized = true;
      motion.teleport(nodePosition, yaw: _yawOfNode());
      return;
    }
    if ((nodePosition - motion.position).length > _externalMoveEpsilon) {
      motion.teleport(nodePosition);
    }
  }

  /// Курс узла из кватерниона поворота вокруг Y — чтобы не терять заданное
  /// при спавне направление (встроенный контроллер стартовал с yaw = 0 и
  /// разворачивал персонажа на первом же кадре).
  double _yawOfNode() {
    final q = node.rotation;
    return math.atan2(
      2.0 * (q.w * q.y + q.x * q.z),
      1.0 - 2.0 * (q.y * q.y + q.z * q.z),
    );
  }

  void _writeToNode() {
    final worldMatrix = vm.Matrix4.compose(
      motion.position,
      vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), motion.yaw),
      node.scale,
    );
    final parent = node.parent;
    if (parent != null) {
      final inverseParent = parent.globalTransform.clone()..invert();
      node.localTransform = inverseParent * worldMatrix;
    } else {
      node.localTransform = worldMatrix;
    }
  }
}
