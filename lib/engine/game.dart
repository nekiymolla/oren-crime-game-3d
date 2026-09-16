import 'dart:math' as math;

import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../core/game_mode.dart';
import '../player/player_input_bridge_component.dart';
import '../vehicles/vehicle.dart';
import '../world/district.dart';
import '../world/terrain.dart';

/// Чистый Dart-класс без импорта Flutter — владеет сценой и игровым
/// состоянием. Виджет (см. game_view.dart) только строит его и пробрасывает
/// тики; вся геймплейная логика живёт здесь и в компонентах узлов.
class Game {
  final Scene scene = Scene();
  late final Node playerNode;
  late final Node cameraNode;
  late final BuiltVehicle vehicle;

  Node? _playerMeshNode;

  /// Публичный, чтобы GameHud мог подключить [CameraControls] — сам
  /// контроллер прикреплён к cameraNode как компонент и двигает камеру
  /// каждый кадр независимо от того, кто шлёт в него drag-события.
  late final FollowCameraController cameraController;

  /// Совпадает с chunkSizeMeters в assets/data/world.json — плейсхолдер-земля
  /// закрывает ровно один чанк, пока не подключена реальная геометрия квартала.
  static const double groundSizeMeters = 200.0;

  /// Рост капсулы-плейсхолдера игрока: totalHeight = height + 2*radius.
  static const double _playerCapsuleRadius = 0.4;
  static const double _playerCapsuleHeight = 1.2;

  /// Насколько близко нужно быть к машине, чтобы сесть в неё.
  static const double _vehicleInteractRadius = 4.0;

  /// true, пока игрок сам крутит камеру пальцем (см. GameHud) — авто-довод
  /// камеры за курсом машины в это время не работает, чтобы не бороться с
  /// рукой игрока.
  bool userIsAdjustingCamera = false;

  /// Скорость авто-довода камеры за курсом машины, рад/с на радиан
  /// расхождения (экспоненциальное сглаживание, не мгновенный доворот).
  static const double _cameraAutoAlignSpeed = 2.5;

  Future<void> load() async {
    await Scene.initializeStaticResources();

    // Плейсхолдер-земля чуть ниже нуля — подложка на случай пустых участков
    // между дорогами/зданиями (osm2world строит поверхности только там, где
    // OSM что-то размечает; наш Overpass-запрос пока берёт только highway и
    // building, без landuse/natural).
    scene.add(buildPlaceholderGround(sizeMeters: groundSizeMeters)
      ..position = vm.Vector3(0, -0.05, 0));
    scene.add(_buildSun());
    _buildSky();

    scene.add(await loadYuzhnyDistrict());

    final movement = ThirdPersonControllerComponent(
      walkSpeed: 4.5,
      runMultiplier: 1.8,
      jumpVelocity: 6.0,
      groundPlaneHeight: 0.0,
    );
    playerNode = _buildPlayerNode()..addComponent(movement);
    scene.add(playerNode);

    vehicle = buildPlaceholderSedan()..node.position = vm.Vector3(-3, 0, 2);
    scene.add(vehicle.node);

    cameraNode = Node()..addComponent(CameraComponent(activateOnMount: true));
    cameraController = FollowCameraController(
      followTarget: playerNode,
      distance: 6.0,
      lookHeight: 1.5,
    );
    cameraNode.addComponent(cameraController);
    scene.add(cameraNode);

    // Движение камеры-относительное ("вперёд" на джойстике = "от камеры",
    // а не "куда сейчас смотрит персонаж") — мосту нужен уже готовый
    // cameraController, поэтому он добавляется последним.
    playerNode.addComponent(PlayerInputBridgeComponent(movement, cameraController));
  }

  /// Сесть в машину / выйти из неё — не даёт сработать, если игрок дальше
  /// [_vehicleInteractRadius] от машины. Переключает и куда едет камера, и
  /// откуда читается джойстик (см. [GameModeState]).
  void toggleVehicle() {
    final vehiclePos = vehicle.node.globalTransform.getTranslation();
    if (gameModeState.mode == ControlMode.onFoot) {
      final playerPos = playerNode.globalTransform.getTranslation();
      if ((playerPos - vehiclePos).length > _vehicleInteractRadius) return;
      gameModeState.mode = ControlMode.driving;
      _playerMeshNode?.visible = false;
      cameraController.followTarget = vehicle.node;
    } else {
      gameModeState.mode = ControlMode.onFoot;
      playerNode.position = vehiclePos + vm.Vector3(2.2, 0, 0);
      _playerMeshNode?.visible = true;
      cameraController.followTarget = playerNode;
    }
  }

  /// Направление, в котором распространяется свет (от солнца к земле).
  static final vm.Vector3 _sunLightDirection = vm.Vector3(-0.4, -1.0, -0.3);

  Node _buildSun() {
    final sunLight = DirectionalLight(intensity: 4.0, castsShadow: true);
    final sunNode = Node()..addComponent(DirectionalLightComponent(sunLight));
    // Компонент светит вдоль local +Z узла, поэтому направление задаётся
    // поворотом узла, а не полем DirectionalLight.direction.
    sunNode.lookAt(_sunLightDirection);
    return sunNode;
  }

  /// Простое градиентное небо-заглушка вместо чёрной пустоты — на нём же
  /// строится ambient-освещение сцены. Заменится на PhysicalSkySource с
  /// суточным циклом в Phase 9 (день/ночь, погода).
  void _buildSky() {
    final sky = GradientSkySource(
      zenithColor: vm.Vector3(0.20, 0.40, 0.68),
      horizonColor: vm.Vector3(0.72, 0.80, 0.85),
      groundColor: vm.Vector3(0.30, 0.30, 0.27),
      sunDirection: -_sunLightDirection,
      sunColor: vm.Vector3(1.0, 0.96, 0.88),
    );
    scene.skybox = Skybox(sky);
    scene.environment = EnvironmentMap.fromSky(sky);
  }

  /// Узел-игрок — точка контакта с землёй (её же читает
  /// ThirdPersonControllerComponent). Меш капсулы — дочерний узел, поднятый
  /// на половину полного роста, чтобы капсула не уходила под землю.
  Node _buildPlayerNode() {
    final node = Node();

    const totalHeight = _playerCapsuleHeight + _playerCapsuleRadius * 2;
    final meshNode = Node(
      mesh: Mesh(
        CapsuleGeometry(radius: _playerCapsuleRadius, height: _playerCapsuleHeight),
        PhysicallyBasedMaterial()..baseColorFactor = vm.Vector4(0.82, 0.18, 0.18, 1.0),
      ),
    )..position = vm.Vector3(0, totalHeight / 2, 0);
    node.add(meshNode);
    _playerMeshNode = meshNode;
    return node;
  }

  /// Общая для всей игры логика тика (таймеры, спавн и т.д.), не привязанная
  /// к одному узлу. Per-node поведение живёт в компонентах, а не здесь.
  void tick(double deltaSeconds) {
    if (gameModeState.mode == ControlMode.driving && !userIsAdjustingCamera) {
      _easeCameraYawToward(vehicle.controller.heading, deltaSeconds);
    }
  }

  /// Плавно доворачивает орбиту камеры к [targetYaw] по кратчайшей дуге —
  /// используется, чтобы камера сама возвращалась за спину машины, когда
  /// игрок не крутит вид сам (см. userIsAdjustingCamera).
  void _easeCameraYawToward(double targetYaw, double deltaSeconds) {
    var diff = targetYaw - cameraController.yaw;
    diff = (diff + math.pi) % (2 * math.pi) - math.pi;
    final t = 1.0 - math.exp(-_cameraAutoAlignSpeed * deltaSeconds);
    cameraController.orbitBy(diff * t, 0);
  }
}
