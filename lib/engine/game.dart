import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../core/game_mode.dart';
import '../core/quality_settings.dart';
import '../pedestrians/pedestrian_system.dart';
import '../player/character_collision_field.dart';
import '../player/character_controller_component.dart';
import '../player/player_input_bridge_component.dart';
import '../police/arrest_state.dart';
import '../police/police_system.dart';
import '../time/day_night.dart';
import '../time/day_night_view.dart';
import '../traffic/traffic_car.dart';
import '../weather/weather.dart';
import '../weather/weather_view.dart';
import '../traffic/traffic_signals.dart';
import '../traffic/traffic_signals_view.dart';
import '../traffic/traffic_system.dart';
import '../police/wanted_state.dart';
import '../police/wanted_system.dart';
import '../vehicles/vehicle.dart';
import '../vehicles/vehicle_spec.dart';
import '../world/district.dart';
import '../world/district_streamer.dart';
import '../world/road_graph.dart';
import '../world/terrain.dart';
import '../world/vegetation.dart';
import '../world/world_config.dart';

/// Чистый Dart-класс без импорта Flutter — владеет сценой и игровым
/// состоянием. Виджет (см. game_view.dart) только строит его и пробрасывает
/// тики; вся геймплейная логика живёт здесь и в компонентах узлов.
/// Что делает кнопка машины в HUD (см. [Game.vehicleInteraction]).
enum VehicleInteraction { enter, exit, carjack }

class Game {
  Game({this.debugShowRoadGraph = false});

  /// Жёлтые линии вдоль дорог (см. `road_graph.dart` — граф пока без
  /// другого визуального потребителя, кроме пешеходов, которым линии не
  /// нужны) — отладочный инструмент, не то, что должен видеть игрок в
  /// обычной игре. Значение приходит из GameHud (там доступен kDebugMode
  /// — Game сам остаётся чистым Dart-классом без импорта Flutter).
  final bool debugShowRoadGraph;

  final Scene scene = Scene();
  late final Node playerNode;
  late final Node cameraNode;
  /// Машина, за рулём которой игрок или в которую садился последней.
  /// Меняется при угоне (см. [_carjack]) и при пересадке в брошенную.
  late BuiltVehicle vehicle;

  /// Машины игрока, брошенные в мире (своя после угона, прошлые угнанные)
  /// — в них можно вернуться. Не больше [_maxParkedPlayerCars]: каждая —
  /// отдельный узел с контроллером, копить их весь сеанс незачем.
  final List<BuiltVehicle> _parkedPlayerCars = [];
  static const int _maxParkedPlayerCars = 3;

  /// Числа вождения угнанной машины — грузятся в load(), потому что сам
  /// угон синхронный (по нажатию кнопки).
  late final VehicleSpec _stolenCarSpec;
  late final DistrictStreamer districtStreamer;
  late final PedestrianSystem pedestrians;
  late final PoliceSystem policeSystem;
  late final TrafficSystem traffic;
  late final TrafficSignals signals;
  late final TrafficSignalsView _signalsView;
  late final RedLightDetector _redLightDetector;
  late final WorldConfig worldConfig;
  final WantedSystem wantedSystem = WantedSystem();

  /// Пресеты качества из assets/data/quality.json (ТЗ, раздел 23).
  /// [quality] — активный; рендерную его часть можно менять на живой сцене
  /// через [applyQuality], мировая (население, деревья) фиксируется на
  /// [load], потому что меняет состав уже созданных систем.
  late final QualityPresets qualityPresets;
  late QualitySettings quality;

  /// Ссылки на то, что [applyQuality] правит при переключении пресета в
  /// рантайме. Хранятся полями, потому что иначе до них не добраться: свет
  /// и небо строятся один раз внутри load().
  DirectionalLight? _sunLight;
  Node? _sunNode;
  GradientSkySource? _sky;

  /// Игровое время. Старт — 16:30 14 октября: через пару реальных минут
  /// закат (~18:30), чтобы суточный цикл было видно сразу. Сутки — 24
  /// минуты игры (минута за секунду).
  final GameClock clock = GameClock(hours: 16.5, dayOfYear: 287);

  /// Суточный цикл на сцене (см. lib/time/).
  late final DayNightView dayNight;

  /// Погода: ясно/облачно/дождь/снег/... и её эффекты (lib/weather/). Старт
  /// — ясно, чтобы первым игрок увидел закат в духе Вайс-Сити.
  final WeatherSystem weather = WeatherSystem(initial: WeatherKind.clear);
  late final WeatherView _weatherView;
  CameraComponent? _cameraComponent;
  Skybox? _skybox;
  EnvironmentMap? _environment;

  /// Плейсхолдер-земля и растительность — под подозрением по результатам
  /// замера: raster держится под сотню миллисекунд даже когда камера смотрит
  /// в пустое небо, значит платим не за геометрию района, а за что-то
  /// полноэкранное и постоянное. Земля 2200x2200 с полным PBR и
  /// environment map закрывает пол-экрана и считает физкорректное освещение
  /// ради плоской зелёной заливки — первый кандидат. Держим ссылки, чтобы
  /// debug-панель могла погасить их по одному и измерить вклад каждого.
  Node? _groundNode;
  Node? _vegetationNode;
  VegetationBatch? _vegetation;

  /// Свой облегчённый контроллер персонажа вместо встроенного
  /// `ThirdPersonControllerComponent` (см. character_motion.dart): 3 луча
  /// обхода препятствий вместо 9 и обход не всего графа сцены, а только
  /// ближних чанков района (см. [_collisionField]).
  CharacterControllerComponent? _movement;
  CharacterCollisionField? _collisionField;

  Node? _playerMeshNode;

  /// Розовые лучи "пешеход → цель" (см. PedestrianSystem.
  /// buildDebugTargetLinesNode) — только в debug-сборке, рядом с жёлтым
  /// дорожным графом. null, если debugShowRoadGraph выключен.
  Node? _pedestrianDebugLinesNode;

  /// Отладочный слой дорожного графа (только при [debugShowRoadGraph]).
  Node? _roadGraphDebugNode;

  /// Для debug-панели: показать/скрыть слой графа и линии целей пешеходов.
  bool get roadGraphDebugVisible => _roadGraphDebugNode?.visible ?? false;
  set roadGraphDebugVisible(bool value) {
    _roadGraphDebugNode?.visible = value;
    _pedestrianDebugLinesNode?.visible = value;
  }

  /// Публичный, чтобы GameHud мог подключить [CameraControls] — сам
  /// контроллер прикреплён к cameraNode как компонент и двигает камеру
  /// каждый кадр независимо от того, кто шлёт в него drag-события.
  late final FollowCameraController cameraController;

  /// С запасом покрывает весь загружаемый чанками район (~1900x1600 м, см.
  /// PROGRESS.md) — плоскость всего 2 треугольника, размер почти бесплатен,
  /// а без запаса игрок на краю района уходит за плейсхолдер-землю в пустоту.
  static const double groundSizeMeters = 2200.0;

  /// Рост капсулы-плейсхолдера игрока: totalHeight = height + 2*radius.
  static const double _playerCapsuleRadius = 0.4;
  static const double _playerCapsuleHeight = 1.2;

  /// Насколько близко нужно быть к машине, чтобы сесть в неё. Публичный —
  /// GameHud использует то же число, чтобы решать, показывать ли кнопку.
  static const double vehicleInteractRadius = 4.0;

  /// Быстрее этого машину потока не угнать — с ходу на скорости водителя
  /// не выдернешь. Трафик сам тормозит перед стоящим на дороге игроком.
  static const double _carjackMaxSpeed = 4.0;

  /// true, пока игрок сам крутит камеру пальцем (см. GameHud) — авто-довод
  /// камеры за курсом машины в это время не работает, чтобы не бороться с
  /// рукой игрока.
  bool userIsAdjustingCamera = false;

  /// Скорость авто-довода камеры за курсом машины, рад/с на радиан
  /// расхождения (экспоненциальное сглаживание, не мгновенный доворот).
  static const double _cameraAutoAlignSpeed = 2.5;

  Future<void> load() async {
    await Scene.initializeStaticResources();

    // Раньше всего остального: пресет задаёт и параметры света/неба/камеры,
    // которые строятся ниже по этому же методу, и размер населения/деревьев.
    qualityPresets = await loadQualityPresets();
    quality = qualityPresets.defaultPreset;
    scene.renderScale = quality.renderScale;
    scene.antiAliasingMode = quality.antiAliasing;

    // Плейсхолдер-земля чуть ниже нуля — подложка на случай пустых участков
    // между дорогами/зданиями (osm2world строит поверхности только там, где
    // OSM что-то размечает, а разметка реального района местами скудная —
    // см. PROGRESS.md).
    final ground = buildPlaceholderGround(sizeMeters: groundSizeMeters)..position = vm.Vector3(0, -0.05, 0);
    _groundNode = ground;
    scene.add(ground);
    scene.add(_buildSun());
    _buildSky();
    final shaderSky = await _loadShaderSky();
    dayNight = DayNightView(
      scene: scene,
      clock: clock,
      sunNode: _sunNode!,
      sunLight: _sunLight!,
      sky: _sky!,
      shadowsAllowed: () => quality.shadowsEnabled,
      onNightFactor: setHeadlightsGlow,
      unlitSurfaces: [ground.mesh!.primitives.first.material as UnlitMaterial],
    );
    _weatherView = WeatherView(
      scene: scene,
      godRaysAllowed: () => quality.godRaysEnabled,
      bloomAllowed: () => quality.bloomEnabled,
      maxParticles: quality.precipitationParticles,
    );
    scene.add(_weatherView.buildNode());
    dayNight.visibleSky = shaderSky;
    // Сразу выставить небо/свет на стартовое время — иначе первый кадр был
    // бы дневным статичным.
    dayNight.update(0, weather: weather.params);

    worldConfig = await loadWorldConfig();
    final districtManifest = await loadDistrictManifest();
    final vegetation = VegetationBatch(maxTrees: quality.maxTrees);
    _vegetation = vegetation;
    final vegetationNode = vegetation.buildNode();
    _vegetationNode = vegetationNode;
    scene.add(vegetationNode);

    // Дорожный граф — настоящий потребитель: NPC-пешеходы ходят по нему.
    // Жёлтые линии-визуализация — только в debug-сборке (debugShowRoadGraph).
    final roadGraph = await loadRoadGraph();
    if (debugShowRoadGraph) {
      // Жёлтый — где ездит трафик, серый — дворовые проезды (service, трафик
      // туда не заезжает), голубой — пешеходные дорожки. Скрыт, пока не
      // включён в debug-панели: постоянно поверх города он мешал смотреть.
      final graphNode = _roadGraphDebugNode = buildRoadGraphDebugNode(
        roadGraph,
        colorOf: (edge) => trafficHighwayTypes.contains(edge.highway)
            ? vm.Vector4(1.0, 0.85, 0.1, 1.0)
            : edge.highway == 'service'
            ? vm.Vector4(0.55, 0.55, 0.55, 1.0)
            : vm.Vector4(0.3, 0.8, 1.0, 1.0),
      )..visible = false;
      scene.add(graphNode);
    }

    pedestrians = PedestrianSystem(graph: roadGraph, raycastRoot: scene.root, population: quality.pedestrianPopulation);
    scene.add(pedestrians.buildNode());
    if (debugShowRoadGraph) {
      _pedestrianDebugLinesNode = pedestrians.buildDebugTargetLinesNode()..visible = false;
      scene.add(_pedestrianDebugLinesNode!);
    }
    policeSystem = await PoliceSystem.create(graph: roadGraph, scene: scene);
    final trafficNetwork = TrafficNetwork(roadGraph);
    signals = TrafficSignals.fromNetwork(trafficNetwork);
    _signalsView = TrafficSignalsView(signals);
    scene.add(_signalsView.buildNode());
    _redLightDetector = RedLightDetector(signals);
    traffic = TrafficSystem(
      network: trafficNetwork,
      scene: scene,
      signals: signals,
      population: quality.trafficPopulation,
    );

    districtStreamer = DistrictStreamer(
      scene: scene,
      manifest: districtManifest,
      radiusCells: worldConfig.streamingRadiusChunks,
      vegetation: vegetation,
      onChunkLoaded: dayNight.registerChunk,
    );
    // Грузим чанки вокруг реальной точки спавна СИНХРОННО с load() (await,
    // не fire-and-forget) — GameView/тики стартуют только после того, как
    // load() завершится (см. GameHud._ready), а PedestrianSystem спавнит
    // популяцию и выбирает первые цели лениво на первом update(). Без этого
    // await здания вокруг спавна могли физически не успеть попасть в сцену
    // к моменту первой проверки _isEdgePassable — путь ошибочно считался
    // "открытым" не из-за бага рейкаста, а из-за отсутствующей геометрии
    // (см. DistrictStreamer.updateAroundPosition, BUGS.md).
    await districtStreamer.updateAroundPosition(worldConfig.playerSpawnPosition);

    // Область, по которой идут лучи персонажа: ближние чанки района плюс
    // машины в пределах досягаемости. Всё остальное (плейсхолдер-земля,
    // растительность, пешеходы, отладочные линии, камера, свет) в обход не
    // попадает вообще — землю заменяет groundPlaneHeight в контроллере.
    final collisionField = _collisionField = CharacterCollisionField(districtStreamer: districtStreamer);

    final movement = _movement = CharacterControllerComponent(
      walkSpeed: 4.5,
      runMultiplier: 1.8,
      jumpVelocity: 6.0,
      groundPlaneHeight: 0.0,
      bodyRadius: _defaultObstacleRadius,
      raycast: collisionField.cast,
    );
    playerNode = _buildPlayerNode()..addComponent(movement);
    playerNode.position = worldConfig.playerSpawnPosition;
    playerNode.rotation = vm.Quaternion.axisAngle(
      vm.Vector3(0, 1, 0),
      worldConfig.playerSpawnHeadingDegrees * math.pi / 180,
    );
    scene.add(playerNode);

    // Рядом со спавном игрока (см. WorldConfig.playerSpawnPosition) — тот же
    // открытый парк, чтобы машина была видна и доступна сразу.
    vehicle = await buildPlaceholderSedan();
    _stolenCarSpec = await loadVehicleSpec('car_sedan_01') ?? fallbackVehicleSpec;
    vehicle.node.position = worldConfig.playerSpawnPosition + vm.Vector3(4, 0, 0);
    scene.add(vehicle.node);

    // Пара припаркованных машин для разнообразия ("больше машин", см.
    // PROGRESS.md) — чисто декоративные (buildStaticVehicleVisual, без
    // VehicleControllerComponent/повреждений), трафик-AI отдельная задача.
    final parkedHatchback = buildStaticVehicleVisual(VehicleArchetype.hatchback)
      ..position = worldConfig.playerSpawnPosition + vm.Vector3(-6, 0, -3)
      ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), math.pi * 0.15);
    final parkedPickup = buildStaticVehicleVisual(VehicleArchetype.pickup)
      ..position = worldConfig.playerSpawnPosition + vm.Vector3(-8, 0, 6)
      ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), -math.pi * 0.4);
    scene.add(parkedHatchback);
    scene.add(parkedPickup);

    // Машины — не часть чанков района, поэтому в коллизионную область они
    // добавляются отдельными корнями (и только когда игрок рядом, иначе
    // каждый луч обходил бы их поддеревья впустую). Патрульные машины
    // приходят колбэком: их набор меняется по звёздам розыска.
    collisionField.addColliderSource(
      () => [vehicle.node, for (final car in _parkedPlayerCars) car.node, parkedHatchback, parkedPickup],
    );
    collisionField.addColliderSource(() => policeSystem.unitNodes);
    collisionField.addColliderSource(() => traffic.carNodes);

    final cameraComponent = CameraComponent(
      projection: PerspectiveProjection(far: quality.drawDistanceMeters),
      activateOnMount: true,
    );
    _cameraComponent = cameraComponent;
    cameraNode = Node()..addComponent(cameraComponent);
    // minPitch по умолчанию -0.15: вверх не посмотреть дальше ~9° над
    // горизонтом — ни луну, ни высокое солнце не увидеть. Разрешаем до
    // ~57°, а камеру при взгляде вверх подтягиваем к персонажу, чтобы не
    // уходила под землю (см. _keepCameraAboveGround).
    cameraController = FollowCameraController(
      followTarget: playerNode,
      distance: _cameraDistance,
      lookHeight: 1.5,
      minPitch: -1.0,
    );
    cameraNode.addComponent(cameraController);
    scene.add(cameraNode);

    // Движение камеры-относительное ("вперёд" на джойстике = "от камеры",
    // а не "куда сейчас смотрит персонаж") — мосту нужен уже готовый
    // cameraController, поэтому он добавляется последним.
    playerNode.addComponent(PlayerInputBridgeComponent(movement, cameraController));
  }

  /// Применяет рендерную часть пресета к уже живой сцене — ради этого
  /// переключатель и нужен: A/B-замер снимается на одном устройстве без
  /// пересборки, а значит сравниваются кадры одной и той же сборки в одном
  /// и том же месте карты.
  ///
  /// Мировая часть пресета (население пешеходов, потолок деревьев) здесь
  /// сознательно НЕ применяется: она меняет состав уже созданных систем —
  /// это перезапуск, а не настройка. После переключения пресета кнопкой
  /// население останется от того пресета, с которым игра стартовала.
  void applyQuality(QualitySettings settings) {
    quality = settings;
    scene.renderScale = settings.renderScale;
    scene.antiAliasingMode = settings.antiAliasing;
    _sunLight
      ?..castsShadow = settings.shadowsEnabled
      ..shadowCascadeCount = settings.shadowCascadeCount
      ..shadowMaxDistance = settings.shadowMaxDistance
      ..shadowMapResolution = settings.shadowMapResolution;
    _cameraComponent?.projection = PerspectiveProjection(far: settings.drawDistanceMeters);
    _applyEnvironmentSettings();
  }

  /// Debug-ручки для замеров: гасят подозреваемых по одному, чтобы увидеть
  /// вклад каждого в кадр. Не игровая логика — дёргаются только из
  /// debug-панели, в релизе её нет.
  bool get groundVisible => _groundNode?.visible ?? false;
  set groundVisible(bool value) => _groundNode?.visible = value;

  bool get vegetationVisible => _vegetationNode?.visible ?? false;
  set vegetationVisible(bool value) => _vegetationNode?.visible = value;

  // Ручки vegetationShadowStatic здесь больше нет: выигрыш измерен (-46.1 мс
  // raster), и shadowStatic стал постоянным поведением VegetationBatch.

  /// Горизонтальные рейкасты игрока (обход препятствий). Встроенный
  /// контроллер кидал 3 высоты x 3 боковых смещения = 9 лучей на кадр плюс
  /// один на землю, и при ходьбе ui подскакивал с 10.3 до 21.6 мс; свой
  /// (см. character_motion.dart) кидает 8 + 1, но по узкой области. Ручка
  /// нужна, чтобы отделить их вклад от остального UI-потока: радиус тела
  /// = 0 отключает именно их, не трогая гравитацию, прыжок и следование за
  /// землёй.
  ///
  /// Это диагностика, а не игровая настройка: без этих лучей игрок проходит
  /// сквозь стены.
  ///
  /// **Прореживать лучи по кадрам нельзя — проверено 19.09.2026, игрок сразу
  /// зашёл сквозь стену.** Цифры соблазнительные (при ходьбе 31 -> 43 FPS,
  /// ui 22.8 -> 16.5), но встроенный контроллер не ВЫТАЛКИВАЕТ из стены, он
  /// ПРЕДОТВРАЩАЕТ вход, смещая движение вдоль препятствия. Пропустив кадр,
  /// игрок оказывается внутри геометрии, и возврата оттуда не предусмотрено.
  /// Рассуждение "за кадр пройдёт 7 см, на следующем вернёт" было неверным.
  /// Путь к экономии здесь — меньше лучей и уже область поиска (свой
  /// контроллер вместо встроенного), а не реже проверки.
  static const double _defaultObstacleRadius = 0.5;

  bool _obstacleAvoidance = true;

  bool get obstacleAvoidance => _obstacleAvoidance;
  set obstacleAvoidance(bool value) {
    _obstacleAvoidance = value;
    _movement?.bodyRadius = value ? _defaultObstacleRadius : 0.0;
  }

  /// Что сейчас сделает кнопка машины (null — ничего, кнопку не
  /// показывать). Зовётся HUD-ом каждый кадр, поэтому без аллокаций сверх
  /// поиска ближайшей машины.
  VehicleInteraction? get vehicleInteraction {
    if (gameModeState.mode == ControlMode.driving) return VehicleInteraction.exit;
    final target = _nearestEnterable();
    if (target == null) return null;
    return target.stolen != null ? VehicleInteraction.carjack : VehicleInteraction.enter;
  }

  /// Ближайшая машина в радиусе посадки: своя (текущая или брошенная) или
  /// машина потока, которую можно угнать.
  ({BuiltVehicle? own, StealableCar? stolen})? _nearestEnterable() {
    final playerPos = playerNode.globalTransform.getTranslation();
    BuiltVehicle? own;
    var ownDistance = vehicleInteractRadius;
    for (final car in [vehicle, ..._parkedPlayerCars]) {
      final distance = (car.node.globalTransform.getTranslation() - playerPos).length;
      if (distance <= ownDistance) {
        ownDistance = distance;
        own = car;
      }
    }
    final stolen = traffic.stealableNear(playerPos, radius: vehicleInteractRadius, maxSpeed: _carjackMaxSpeed);
    if (stolen != null && (own == null || (stolen.car.position - playerPos).length < ownDistance)) {
      return (own: null, stolen: stolen);
    }
    return own == null ? null : (own: own, stolen: null);
  }

  /// Сесть в машину (свою или угнать из потока) / выйти — по ближайшей
  /// цели [vehicleInteraction]. Переключает и куда едет камера, и откуда
  /// читается джойстик (см. [GameModeState]).
  void toggleVehicle() {
    if (gameModeState.mode == ControlMode.driving) {
      final vehiclePos = vehicle.node.globalTransform.getTranslation();
      final heading = vehicle.controller.heading;
      // Выходим с водительской стороны (слева), а не всегда в +X мира:
      // так игрок не оказывается в доме или под колёсами соседа.
      final left = vm.Vector3(math.cos(heading), 0, -math.sin(heading));
      gameModeState.mode = ControlMode.onFoot;
      playerNode.position = vehiclePos + left * 2.0;
      _playerMeshNode?.visible = true;
      cameraController.followTarget = playerNode;
      return;
    }

    final target = _nearestEnterable();
    if (target == null) return;
    final stolen = target.stolen;
    if (stolen != null) {
      _carjack(stolen);
    } else if (!identical(target.own, vehicle)) {
      _parkedPlayerCars.remove(target.own);
      _parkPlayerCar(vehicle);
      vehicle = target.own!;
    }
    gameModeState
      ..mode = ControlMode.driving
      ..activeVehicle = vehicle.controller;
    _playerMeshNode?.visible = false;
    cameraController.followTarget = vehicle.node;
  }

  /// Угон: машина уходит из потока, на её месте собирается управляемая
  /// того же вида, водитель выскакивает и убегает, розыск — звезда.
  void _carjack(StealableCar stolen) {
    final car = stolen.car;
    traffic.removeCar(car);

    final built = buildVehicleWithSpec(stolen.look, _stolenCarSpec);
    built.node
      ..position = car.position
      ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), car.heading);
    built.controller.heading = car.heading;
    scene.add(built.node);

    _parkPlayerCar(vehicle);
    vehicle = built;

    final left = vm.Vector3(math.cos(car.heading), 0, -math.sin(car.heading));
    pedestrians.spawnFleeingDriver(car.position + left * 1.6, playerNode.globalTransform.getTranslation());
    wantedSystem.reportMinorCrime();
  }

  void _parkPlayerCar(BuiltVehicle car) {
    _parkedPlayerCars.add(car);
    if (_parkedPlayerCars.length > _maxParkedPlayerCars) {
      scene.remove(_parkedPlayerCars.removeAt(0).node);
    }
  }

  /// Направление, в котором распространяется свет (от солнца к земле).
  static final vm.Vector3 _sunLightDirection = vm.Vector3(-0.4, -1.0, -0.3);

  Node _buildSun() {
    final sunLight = DirectionalLight(
      intensity: 4.0,
      castsShadow: quality.shadowsEnabled,
      shadowCascadeCount: quality.shadowCascadeCount,
      shadowMaxDistance: quality.shadowMaxDistance,
      shadowMapResolution: quality.shadowMapResolution,
    );
    _sunLight = sunLight;
    final sunNode = _sunNode = Node()..addComponent(DirectionalLightComponent(sunLight));
    // Компонент светит вдоль local +Z узла, поэтому направление задаётся
    // поворотом узла, а не полем DirectionalLight.direction.
    sunNode.lookAt(_sunLightDirection);
    return sunNode;
  }

  /// Видимое небо — шейдер assets/shaders/crime_sky.fmat: чёткий диск
  /// солнца, луна с фазами, звёзды. Освещение сцены по-прежнему
  /// запекается с градиентного неба ([_buildSky]): иначе HDR-диск солнца
  /// попал бы в отражения и светил в машинах даже ночью. Не загрузилось
  /// (старая сборка без шейдера) — остаётся градиентное.
  Future<PreprocessedSky?> _loadShaderSky() async {
    try {
      final sky = await loadFmatSky('assets/shaders/crime_sky.fmat');
      final skybox = Skybox(sky);
      scene.skybox = skybox;
      _skybox = skybox;
      _applyEnvironmentSettings();
      return sky;
    } catch (error) {
      // ignore: avoid_print
      print('Небо-шейдер не загрузилось, остаётся градиентное: $error');
      return null;
    }
  }

  /// Градиентное небо — на нём же строится ambient-освещение сцены. Цвета
  /// и солнце в нём каждый кадр выставляет суточный цикл (DayNightView);
  /// освещение от неба запекается один раз, дальше меняется только его
  /// яркость (Scene.environmentIntensity) — перезапекать каждый кадр на
  /// слабом Android дорого. Физическое небо (PhysicalSkySource) красивее
  /// на закате, но тоже дороже — отложено.
  void _buildSky() {
    final sky = GradientSkySource(
      zenithColor: vm.Vector3(0.20, 0.40, 0.68),
      horizonColor: vm.Vector3(0.72, 0.80, 0.85),
      groundColor: vm.Vector3(0.30, 0.30, 0.27),
      sunDirection: -_sunLightDirection,
      sunColor: vm.Vector3(1.0, 0.96, 0.88),
      // Крупный мягкий диск солнца (по умолчанию 400 — точка): с bloom и
      // бликом линз — солнце в духе Вайс-Сити.
      sunSharpness: 90.0,
    );
    _sky = sky;
    final skybox = Skybox(sky);
    final environment = EnvironmentMap.fromSky(sky);
    scene.skybox = skybox;
    scene.environment = environment;
    _skybox = skybox;
    _environment = environment;

    // Дешёвый проход света/пост-обработки (flutter_scene-looks skill) — без
    // SSR/fog/god rays/grain: на слабом Android (RMX5303, см. PROGRESS.md)
    // уже упирались в fill-rate, тяжёлые эффекты добавлять рано. AO —
    // half-res специально ради этого же бюджета.
    //
    // EnvironmentSettings.applyTo() — ПОЛНЫЙ снимок вида: безусловно
    // перезаписывает scene.skybox/scene.environment своими полями (см.
    // applyLookTo в пакете), так что skybox/environment нужно передать
    // явно — иначе он зануляет только что установленное небо (было: небо
    // стало чёрным).
    _applyEnvironmentSettings();
  }

  /// Пересобирает EnvironmentSettings под текущий [quality]. Отдельным
  /// методом, а не внутри _buildSky, потому что переключение пресета в
  /// рантайме обязано пересоздать снимок целиком: EnvironmentSettings —
  /// это ПОЛНЫЙ снимок вида, точечно "выключить bloom" в уже присвоенном
  /// объекте нельзя.
  void _applyEnvironmentSettings() {
    scene.environmentSettings = EnvironmentSettings(
      skybox: _skybox,
      environment: _environment,
      toneMapping: ToneMappingMode.aces,
      exposure: 1.0,
      colorGradingEnabled: true,
      saturation: 1.1,
      contrast: 1.05,
      temperature: 0.05,
      bloomEnabled: quality.bloomEnabled,
      bloomThreshold: 1.1,
      bloomIntensity: 0.18,
      bloomScatter: 0.6,
      // obscurance — самый дешёвый метод AO (и дефолтный в пакете);
      // groundTruth даёт кадр вдвое дороже (60 -> 32 FPS на iPhone 13 в
      // тесте) ради качества, которое на этом масштабе сцены не окупается.
      //
      // Выключение AO заодно убирает depth prepass (в движке wantDepthPrepass
      // завязан на ambientOcclusion.enabled), а с ним early-Z, который режет
      // overdraw — так что на fill-bound сцене выключение AO может выйти
      // МЕДЛЕННЕЕ. Проверять замером, а не считать очевидным.
      ambientOcclusionEnabled: quality.ambientOcclusionEnabled,
      ambientOcclusionMethod: AmbientOcclusionMethod.obscurance,
      ambientOcclusionHalfResolution: true,
      ambientOcclusionIntensity: 0.6,
      vignetteEnabled: true,
      vignetteIntensity: 0.15,
    );
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

  /// Узел, за которым сейчас "следит" мир — игрок пешком или машина за
  /// рулём. Публичный, чтобы HUD мог показать координаты в debug-оверлее
  /// (см. GameView) без дублирования этой развилки по gameModeState.
  Node get trackedNode => gameModeState.mode == ControlMode.driving ? vehicle.node : playerNode;

  /// Общая для всей игры логика тика (таймеры, спавн и т.д.), не привязанная
  /// к одному узлу. Per-node поведение живёт в компонентах, а не здесь.
  void tick(double deltaSeconds) {
    final trackedPosition = trackedNode.globalTransform.getTranslation();
    districtStreamer.updateAroundPosition(trackedPosition);

    // Пересобираем узкий список корней обхода для лучей персонажа — раз в
    // кадр и ДО тика компонентов (SceneView.onTick сначала зовёт game.tick,
    // потом рисует сцену, а компоненты тикают на отрисовке). За рулём
    // контроллер персонажа выключен (см. PlayerInputBridgeComponent), так
    // что и отбор не нужен.
    if (gameModeState.mode == ControlMode.onFoot) {
      _collisionField?.refresh(playerNode.globalTransform.getTranslation());
    }
    // Возвращает кэш теней растительности, если в этом кадре досадили
    // деревья при загрузке чанка (см. VegetationBatch.commitShadowCache).
    _vegetation?.commitShadowCache();

    final isDriving = gameModeState.mode == ControlMode.driving;
    final hits = pedestrians.update(
      deltaSeconds,
      trackedPosition,
      vehiclePosition: isDriving ? vehicle.node.globalTransform.getTranslation() : null,
      vehicleSpeed: isDriving ? vehicle.controller.speed : 0.0,
    );
    if (_pedestrianDebugLinesNode != null) {
      pedestrians.updateDebugTargetLines(_pedestrianDebugLinesNode!);
    }
    wantedSystem.update(
      deltaSeconds,
      pedestrianHits: hits,
      isSpeeding: isDriving && vehicle.controller.speed >= wantedSystem.speedThreshold,
    );

    _updateWeather(deltaSeconds);
    signals.advance(deltaSeconds);
    _signalsView.update();
    traffic.update(deltaSeconds, trackedPosition, external: _trafficObstacles(isDriving));
    // Проезд на красный — только за рулём; детектор держит "в каком
    // перекрёстке был", поэтому зовётся каждый кадр, а пешком — с нулевой
    // скоростью (не нарушение, но зона перекрёстка обновляется).
    final ranRedLight = _redLightDetector.update(
      trackedPosition,
      isDriving ? vehicle.controller.velocityXZ : vm.Vector2.zero(),
    );
    if (ranRedLight) wantedSystem.reportMinorCrime();

    final caught = policeSystem.update(deltaSeconds, trackedPosition);
    if (caught) _handleArrest();

    if (isDriving && !userIsAdjustingCamera) {
      _easeCameraYawToward(vehicle.controller.heading, deltaSeconds);
    }
    _keepCameraAboveGround();
  }

  /// Погода и суточный цикл — в одном месте, порядок важен: молния ->
  /// свет/небо (с вспышкой) -> пост-эффекты и осадки под этот свет ->
  /// смена погоды по игровым часам.
  void _updateWeather(double deltaSeconds) {
    final params = weather.params;
    _weatherView.updateLightning(deltaSeconds, params);
    dayNight.update(deltaSeconds, weather: params, lightningFlash: _weatherView.lightningFlash);
    _weatherView.update(deltaSeconds, dayNight.lighting!, params, cameraNode.globalTransform.getTranslation());
    weather.update(
      deltaSeconds,
      gameHoursPassed: deltaSeconds * clock.gameMinutesPerSecond / 60.0,
      dayOfYear: clock.dayOfYear,
    );
    _vegetation?.setSnowCover(params.snowCover);
  }

  /// То, перед чем тормозит трафик помимо друг друга: игрок (пешком или
  /// его машина), полиция, пешеходы. Радиусы — полуширины в плане.
  Iterable<TrafficObstacle> _trafficObstacles(bool isDriving) sync* {
    if (isDriving) {
      yield (position: vehicle.node.globalTransform.getTranslation(), radius: 1.0);
    } else {
      yield (position: playerNode.globalTransform.getTranslation(), radius: _playerCapsuleRadius);
      // Пустая машина игрока тоже стоит где-то — возможно, посреди дороги.
      yield (position: vehicle.node.globalTransform.getTranslation(), radius: 1.0);
    }
    for (final car in _parkedPlayerCars) {
      yield (position: car.node.globalTransform.getTranslation(), radius: 1.0);
    }
    for (final node in policeSystem.unitNodes) {
      yield (position: node.globalTransform.getTranslation(), radius: 1.0);
    }
    for (final position in pedestrians.positions) {
      yield (position: position, radius: PedestrianSystem.bodyRadius);
    }
  }

  /// Игрока поймали (см. PoliceSystem.update) — розыск сбрасывается,
  /// патрульные машины исчезают сразу (как в GTA на экране "задержан", не
  /// постепенно), игрок телепортируется к точке спавна (условная
  /// "безопасная точка" — отдельного полицейского участка на карте пока
  /// нет). HUD показывает баннер через ArrestState (см. arrest_banner.dart).
  void _handleArrest() {
    wantedState.stars = 0;
    policeSystem.clearUnits();
    arrestState.trigger();
    if (gameModeState.mode == ControlMode.driving) toggleVehicle();
    playerNode.position = worldConfig.playerSpawnPosition;
    cameraController.followTarget = playerNode;
  }

  /// Дистанция камеры за игроком в обычном положении.
  static const double _cameraDistance = 6.0;

  /// Камера ниже точки взгляда (pitch < 0 — смотрим вверх) ушла бы под
  /// землю: подтягиваем её к персонажу так, чтобы она оставалась хотя бы на
  /// 0.3 м над землёй. Как в GTA — посмотреть на небо значит "присесть"
  /// камерой к плечу.
  void _keepCameraAboveGround() {
    final pitch = cameraController.pitch;
    if (pitch >= 0) {
      cameraController.distance = _cameraDistance;
      return;
    }
    const clearance = 1.5 - 0.3; // lookHeight минус запас над землёй
    cameraController.distance = math.min(_cameraDistance, clearance / math.sin(-pitch));
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
