import 'package:flutter_scene/kit.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../player/player_input_bridge_component.dart';
import '../world/terrain.dart';

/// Чистый Dart-класс без импорта Flutter — владеет сценой и игровым
/// состоянием. Виджет (см. game_view.dart) только строит его и пробрасывает
/// тики; вся геймплейная логика живёт здесь и в компонентах узлов.
class Game {
  final Scene scene = Scene();
  late final Node playerNode;
  late final Node cameraNode;

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

  Future<void> load() async {
    await Scene.initializeStaticResources();

    scene.add(buildPlaceholderGround(sizeMeters: groundSizeMeters));
    scene.add(_buildSun());
    _buildSky();

    final movement = ThirdPersonControllerComponent(
      walkSpeed: 4.5,
      runMultiplier: 1.8,
      jumpVelocity: 6.0,
      groundPlaneHeight: 0.0,
    );
    playerNode = _buildPlayerNode()..addComponent(movement);
    scene.add(playerNode);

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
    return node;
  }

  /// Общая для всей игры логика тика (таймеры, спавн и т.д.), не привязанная
  /// к одному узлу. Per-node поведение живёт в компонентах, а не здесь.
  void tick(double deltaSeconds) {}
}
