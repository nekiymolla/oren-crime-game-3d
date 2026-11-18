import 'debug/performance_probe.dart';
import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../audio/audio_system.dart';
import '../characters/character_animation.dart';
import '../characters/character_library.dart';
import '../characters/character_model.dart';
import '../core/game_mode.dart';
import '../core/platform.dart';
import '../core/input/input_state.dart';
import '../economy/pickups.dart';
import '../economy/pickups_view.dart';
import '../economy/wallet.dart';
import 'hud_info.dart';
import '../core/quality_settings.dart';
import '../pedestrians/pedestrian_system.dart';
import '../player/character_collision_field.dart';
import '../player/character_motion.dart' show CharacterRayHit;
import '../player/character_controller_component.dart';
import '../player/game_camera_controller.dart';
import '../player/player_health.dart';
import '../player/player_input_bridge_component.dart';
import '../player/death_state.dart';
import '../police/arrest_state.dart';
import '../properties/property.dart';
import '../properties/property_markers_view.dart';
import '../save/save_data.dart';
import '../save/save_store.dart';
import '../police/police_officer.dart';
import '../police/police_system.dart';
import '../time/day_night.dart';
import '../time/day_night_view.dart';
import '../traffic/traffic_car.dart';
import '../weather/weather.dart';
import '../weather/weather_view.dart';
import '../weather/wet_roads_view.dart';
import '../traffic/traffic_signals.dart';
import '../traffic/traffic_signals_view.dart';
import '../traffic/traffic_system.dart';
import '../police/wanted_state.dart';
import '../police/wanted_system.dart';
import '../vehicles/vehicle.dart';
import '../vehicles/vehicle_models.dart';
import '../vehicles/vehicle_spec.dart';
import '../vehicles/vehicle_controller_component.dart';
import '../weapons/player_shooting.dart';
import '../weapons/weapon_config.dart';
import '../weapons/weapon_effects_view.dart';
import '../weapons/weapon_state.dart';
import '../world/building_facades.dart';
import '../world/district.dart';
import '../world/district_streamer.dart';
import '../world/city_map.dart';
import '../world/city_surface.dart';
import '../world/street_lights.dart';
import '../world/nav_grid.dart';
import '../world/neon_signs.dart';
import '../world/road_graph.dart';
import '../world/terrain.dart';
import '../world/terrain_height.dart';
import '../world/tree_placement.dart';
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
  late final CityMap cityMap;
  late final StreetLights streetLights;
  final benchRest = BenchRest();
  int _restDamageRevision = 0;
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
  late final WetRoadsView _wetRoads;

  /// Окна на стенах домов (lib/world/building_facades.dart).
  final BuildingFacades _facades = BuildingFacades();

  /// Неоновые вывески на фасадах вдоль крупных улиц (lib/world/neon_signs.dart).
  NeonSignsView? _neon;
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
  late final TerrainHeight terrain;
  TexturedGround? _terrainView;
  Node? _vegetationNode;
  VegetationBatch? _vegetation;

  /// Свой облегчённый контроллер персонажа вместо встроенного
  /// `ThirdPersonControllerComponent` (см. character_motion.dart): 3 луча
  /// обхода препятствий вместо 9 и обход не всего графа сцены, а только
  /// ближних чанков района (см. [_collisionField]).
  CharacterControllerComponent? _movement;
  CharacterCollisionField? _collisionField;

  Node? _playerMeshNode;

  /// Модели людей (assets/data/characters.json); null — не загрузились,
  /// тогда все остаются капсулами.
  CharacterLibrary? _characters;

  /// Модель игрока (null — капсула).
  CharacterModel? _playerModel;

  /// В этом кадре был выстрел — модель игрока дёргает отдачей.
  bool _firedThisFrame = false;

  /// Часы мигалок патрульных машин.
  double _sirenSeconds = 0.0;

  /// Отладочный слой дорожного графа (только при [debugShowRoadGraph]).
  Node? _roadGraphDebugNode;

  /// Для debug-панели: показать/скрыть слой дорожного графа.
  bool get roadGraphDebugVisible => _roadGraphDebugNode?.visible ?? false;
  set roadGraphDebugVisible(bool value) {
    _roadGraphDebugNode?.visible = value;
  }

  /// Публичный, чтобы GameHud мог подключить [CameraControls] — сам
  /// контроллер прикреплён к cameraNode как компонент и двигает камеру
  /// каждый кадр независимо от того, кто шлёт в него drag-события.
  late final GameCameraController cameraController;

  /// Оружие в руках (lib/weapons/) — HUD читает патроны и перезарядку.
  late final WeaponState weapon;
  late final PlayerShooting _shooting;
  late final WeaponEffectsView _weaponEffects;

  /// Сколько ещё секунд камера держится за плечом после выстрела — чтобы
  /// между нажатиями она не прыгала туда-обратно.
  double _aimHoldSeconds = 0.0;
  static const double _aimHoldAfterShot = 1.5;

  /// Целимся сейчас — HUD показывает прицел.
  bool get isAiming => cameraController.aiming;

  /// Здоровье игрока — по нему стреляет полиция (lib/police/police_officers.dart).
  final PlayerHealth playerHealth = PlayerHealth();

  /// Сколько ещё секунд игрок лежит убитым до возрождения (0 — жив).
  double _deathSeconds = 0.0;
  static const double _deathLieSeconds = 3.5;

  bool get isDead => _deathSeconds > 0.0;

  /// Деньги игрока (lib/economy/) — HUD показывает баланс и операции.
  late final Wallet wallet;
  late final EconomyConfig _economy;
  late final PickupField _pickups;
  late final PickupsView _pickupsView;
  final math.Random _random = math.Random();

  /// Недвижимость (lib/properties/): что куплено, где возрождаться.
  late final PropertySystem properties;
  late final PropertyMarkersView _propertyMarkers;

  /// Звук (lib/audio/).
  late final AudioSystem audio;

  /// Машины, к которым уже подцеплен звук удара.
  final Set<BuiltVehicle> _crashHooked = {};

  /// Шла ли перезарядка в прошлом кадре — щелчок звучит на её начале.
  bool _wasReloading = false;

  /// Сохранение (lib/save/): файл в документах приложения.
  final SaveStore _saveStore = SaveStore();

  /// Когда последний раз сохранились — HUD показывает "Сохранено".
  DateTime? lastSavedAt;

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
  double _cameraManualGrace = 0.0;

  /// Скорость авто-довода камеры за курсом машины, рад/с на радиан
  /// расхождения (экспоненциальное сглаживание, не мгновенный доворот).
  static const double _cameraAutoAlignSpeed = 2.5;

  Future<void> load() async {
    await Scene.initializeStaticResources();

    // Раньше всего остального: пресет задаёт и параметры света/неба/камеры,
    // которые строятся ниже по этому же методу, и размер населения/деревьев.
    qualityPresets = await loadQualityPresets();
    try {
      await VehicleModels.load();
    } catch (error) {
      // ignore: avoid_print
      print('VehicleModels: модели машин не загрузились ($error) — кубы');
    }
    try {
      _characters = await CharacterLibrary.load();
    } catch (error) {
      // Без моделей игра остаётся играбельной на капсулах.
      // ignore: avoid_print
      print('CharacterLibrary: модели людей не загрузились ($error) — капсулы');
    }
    quality = qualityPresets.defaultPreset;
    scene.renderScale = quality.renderScale;
    scene.antiAliasingMode = quality.antiAliasing;

    // Плейсхолдер-земля чуть ниже нуля — подложка на случай пустых участков
    // между дорогами/зданиями (osm2world строит поверхности только там, где
    // OSM что-то размечает, а разметка реального района местами скудная —
    // см. PROGRESS.md).
    cityMap = await CityMap.load();
    _facades.profiles = cityMap.facadeProfiles;
    final nav = protectCitySurfaces(await NavGrid.load(), cityMap.surfaces);
    terrain = TerrainHeight(nav);
    streetLights = StreetLights(cityMap);
    scene.add(streetLights.node);
    final textured = await TexturedGround.load(
      sizeMeters: groundSizeMeters,
      height: terrain,
      textured: quality.texturedGround,
    );
    _terrainView = textured;
    textured?.updateAround(vm.Vector3(-79, 0, 17));
    final ground =
        (textured?.node ?? buildPlaceholderGround(sizeMeters: groundSizeMeters))
          ..position = vm.Vector3(0, textured == null ? -0.05 : 0, 0);
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
      onNightFactor: (night) {
        setHeadlightsGlow(night);
        _facades.night = night;
      },
      unlitSurfaces: [
        if (ground.mesh?.primitives.first.material
            case final UnlitMaterial flat)
          flat,
      ],
      onUnlitTint: textured?.update,
    );
    _weatherView = WeatherView(
      scene: scene,
      godRaysAllowed: () => quality.godRaysEnabled,
      bloomAllowed: () => quality.bloomEnabled,
      maxParticles: quality.precipitationParticles,
    );
    scene.add(_weatherView.buildNode());
    _wetRoads = WetRoadsView(
      scene: scene,
      reflectionsAllowed: () => quality.wetReflectionsEnabled,
    );
    dayNight.visibleSky = shaderSky;
    if (neonSignsEnabled) await _buildNeon();
    // Сразу выставить небо/свет на стартовое время — иначе первый кадр был
    // бы дневным статичным.
    dayNight.update(0, weather: weather.params);

    worldConfig = await loadWorldConfig();
    final districtManifest = await loadDistrictManifest();
    if (desktopControls && districtManifest.cells.length <= 64) {
      await prewarmDistrictTemplates(districtManifest);
    }
    final vegetation = VegetationBatch(maxTrees: quality.maxTrees);
    vegetation.groundHeightAt = terrain.heightAt;
    vegetation.groundClearance = (x, z, radius) =>
        isTreeGroundClear(nav, x, z, radius) && cityMap.treeClear(x, z, radius);
    // Authored rows are explicitly marked inferred in city_map.json.
    // Prioritise their positions before generic grass scatter fills the cap.
    for (final tree in cityMap.fixtures.where((f) => f.kind == 'tree')) {
      if (isTreeGroundClear(nav, tree.x, tree.z, 2.7)) {
        vegetation.addTree(
          tree.position,
          scale: .82 + ((tree.x.abs() * .13) % .3),
        );
      }
    }
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

    // Навигационная сетка (асфальт/тротуар/земля/дома) — по ней ходят
    // пешеходы и проверяются полосы трафика (lib/world/nav_grid.dart).
    pedestrians = PedestrianSystem(
      nav: nav,
      groundHeightAt: terrain.heightAt,
      population: quality.pedestrianPopulation,
      characters: _characters,
    );
    scene.add(pedestrians.buildNode());
    bool onAsphalt(vm.Vector3 from, vm.Vector3 to) =>
        nav.badFraction(from.x, from.z, to.x, to.z, nav.isDrivable) <= 0.05;
    policeSystem = await PoliceSystem.create(
      graph: roadGraph,
      scene: scene,
      edgeIsClear: onAsphalt,
      characters: _characters,
    );
    policeSystem.officers.groundHeightAt = terrain.heightAt;
    final trafficNetwork = TrafficNetwork(
      roadGraph,
      // Полоса — только по асфальту (допуск 5% на края клеток сетки).
      laneIsClear: onAsphalt,
    );
    // ignore: avoid_print
    print(
      'Трафик: отброшено полос не по асфальту: ${trafficNetwork.rejectedLaneCount}',
    );
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
      onChunkUnloaded: (chunk) {
        _facades.unregisterChunk(chunk);
        streetLights.unregisterChunk(chunk);
      },
      onChunkPrepare: _facades.registerChunk,
      onChunkLoaded: (chunk) {
        streetLights.registerChunk(chunk);
        dayNight.registerChunk(chunk);
        _wetRoads.registerChunk(chunk);
      },
    );
    // Грузим чанки вокруг реальной точки спавна СИНХРОННО с load() (await,
    // не fire-and-forget) — GameView/тики стартуют только после того, как
    // load() завершится (см. GameHud._ready), а PedestrianSystem спавнит
    // популяцию и выбирает первые цели лениво на первом update(). Без этого
    // await здания вокруг спавна могли физически не успеть попасть в сцену
    // к моменту первой проверки _isEdgePassable — путь ошибочно считался
    // "открытым" не из-за бага рейкаста, а из-за отсутствующей геометрии
    // (см. DistrictStreamer.updateAroundPosition, BUGS.md).
    await districtStreamer.updateAroundPosition(
      worldConfig.playerSpawnPosition,
    );

    // Область, по которой идут лучи персонажа: ближние чанки района плюс
    // машины в пределах досягаемости. Всё остальное (плейсхолдер-земля,
    // растительность, пешеходы, отладочные линии, камера, свет) в обход не
    // попадает вообще — землю заменяет groundPlaneHeight в контроллере.
    final collisionField = _collisionField = CharacterCollisionField(
      districtStreamer: districtStreamer,
      additionalRaycast: (origin, direction, distance) {
        final fence = cityMap.castBarriers(origin, direction, distance);
        final hit = vegetation.castTrunks(
          origin,
          direction,
          fence?.distance ?? distance,
        );
        if (hit == null) return fence;
        return CharacterRayHit(distance: hit.distance, normal: hit.normal);
      },
    );

    final movement = _movement = CharacterControllerComponent(
      walkSpeed: 1.65,
      runMultiplier: 3.3,
      jumpVelocity: 6.0,
      groundPlaneHeight: 0.0,
      groundHeightAt: terrain.heightAt,
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
    vehicle.controller.groundHeightAt = terrain.heightAt;
    _stolenCarSpec =
        await loadVehicleSpec('car_sedan_01') ?? fallbackVehicleSpec;
    vehicle.node.position =
        worldConfig.playerSpawnPosition + vm.Vector3(4, 0, 0);
    scene.add(vehicle.node);

    // Two accessible parked cars offer a slow agile compact and a heavy SUV.
    final parked = [
      await buildVehicle(VehicleArchetype.hatchback),
      await buildVehicle(VehicleArchetype.suv),
    ];
    for (var i = 0; i < parked.length; i++) {
      final car = parked[i];
      car.node.position = cityMap.parking.length > i
          ? cityMap.parking[i].position
          : worldConfig.playerSpawnPosition + vm.Vector3(-6.0 - i * 3, 0, 6);
      car.controller.heading = cityMap.parking.length > i
          ? cityMap.parking[i].yaw
          : 0;
      car.node.rotation = vm.Quaternion.axisAngle(
        vm.Vector3(0, 1, 0),
        car.controller.heading,
      );
      car.controller.groundHeightAt = terrain.heightAt;
      scene.add(car.node);
      _parkedPlayerCars.add(car);
    }
    for (final car in [vehicle, ...parked]) {
      _hookCrashSound(car);
    }
    collisionField.addColliderSource(
      () => [
        vehicle.node,
        for (final car in _parkedPlayerCars) car.node,
        ..._decorCars,
      ],
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
    cameraController = GameCameraController(
      followTarget: playerNode,
      distance: _cameraDistance,
      lookHeight: 1.5,
      minPitch: -1.0,
      obstructionRaycast: _castCameraObstruction,
    );
    cameraNode.addComponent(cameraController);
    scene.add(cameraNode);

    // Движение камеры-относительное ("вперёд" на джойстике = "от камеры",
    // а не "куда сейчас смотрит персонаж") — мосту нужен уже готовый
    // cameraController, поэтому он добавляется последним.
    playerNode.addComponent(
      PlayerInputBridgeComponent(
        movement,
        cameraController,
        isLocked: () => isDead,
      ),
    );

    _economy = await loadEconomyConfig();
    wallet = Wallet(_economy.startingMoney);
    _pickups = PickupField(
      lifetimeSeconds: _economy.pickupLifetimeSeconds,
      collectRadius: _economy.pickupRadius,
    );
    _pickupsView = PickupsView(_pickups);
    scene.add(_pickupsView.buildNode());

    properties = PropertySystem(await loadProperties());
    _propertyMarkers = PropertyMarkersView(properties);
    scene.add(_propertyMarkers.buildNode());

    final weapons = await loadWeaponCatalog();
    weapon = WeaponState(weapons.defaultWeapon);
    _shooting = PlayerShooting(
      weapon: weapon,
      targets: CombinedShootTargets([pedestrians, policeSystem.officers]),
      worldRaycast: _bulletRaycast,
    );
    scene.add(policeSystem.officers.buildNode());
    _weaponEffects = WeaponEffectsView();
    scene.add(_weaponEffects.buildNode());

    audio = AudioSystem(scene);
    await audio.load();

    // Последним: сохранение перекрывает стартовые значения всего выше.
    final save = await _saveStore.read();
    if (save != null) _applySave(save);
    await _warmUpScene();
  }

  Future<void> _warmUpScene() async {
    final hour = clock.hours;
    try {
      // Prepare both lighting pipelines and all loaded meshes behind the
      // loading screen, rather than compiling a night variant during a drive.
      for (final lightHour in [13.0, 23.0, hour]) {
        clock.hours = lightHour;
        tick(0);
        scene.update(0);
        final camera = scene.camera;
        if (camera != null) {
          await scene.warmUp([
            RenderView(camera: camera),
          ], includeOffscreen: true);
        }
      }
    } finally {
      clock.hours = hour;
      tick(0);
      scene.update(0);
    }
  }

  /// Снимок прогресса для сохранения.
  SaveData _snapshot() => SaveData(
    money: wallet.balance,
    ownedProperties: properties.owned.toList(),
    position: playerNode.globalTransform.getTranslation(),
    yaw: _movement?.motion.yaw ?? 0.0,
    health: playerHealth.health,
    armor: playerHealth.armor,
    weaponId: weapon.config.id,
    ammoInMagazine: weapon.ammoInMagazine,
    reserveAmmo: weapon.reserveAmmo,
    clockHours: clock.hours,
    dayOfYear: clock.dayOfYear,
    weather: weather.kind.name,
    qualityPreset: quality.name,
  );

  void _applySave(SaveData save) {
    wallet.restore(save.money);
    properties.owned
      ..clear()
      ..addAll(
        save.ownedProperties.where(
          (id) => properties.properties.any((p) => p.id == id),
        ),
      );
    playerNode.position = save.position;
    _movement?.teleport(save.position, yaw: save.yaw);
    playerHealth
      ..health = save.health.clamp(1.0, PlayerHealth.maxHealth)
      ..armor = save.armor.clamp(0.0, PlayerHealth.maxArmor);
    if (save.weaponId == weapon.config.id) {
      weapon
        ..ammoInMagazine = save.ammoInMagazine.clamp(
          0,
          weapon.config.magazineSize,
        )
        ..reserveAmmo = save.reserveAmmo.clamp(0, 9999);
    }
    clock
      ..hours = save.clockHours.clamp(0.0, 23.99)
      ..dayOfYear = save.dayOfYear;
    final savedWeather = WeatherKind.values.where(
      (kind) => kind.name == save.weather,
    );
    if (savedWeather.isNotEmpty) {
      weather.setWeather(savedWeather.first, immediately: true);
    }
    final preset = qualityPresets.presets[save.qualityPreset];
    if (preset != null) applyQuality(preset);
  }

  /// Сохраниться у своего дома. false — не здесь или идёт розыск.
  Future<bool> saveGame() async {
    if (!(propertyInteraction?.canSave ?? false)) return false;
    await _saveStore.write(_snapshot());
    lastSavedAt = DateTime.now();
    audio.saved();
    return true;
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
    _cameraComponent?.projection = PerspectiveProjection(
      far: settings.drawDistanceMeters,
    );
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
    if (isDead) return null;
    if (gameModeState.mode == ControlMode.driving) {
      return VehicleInteraction.exit;
    }
    final target = _nearestEnterable();
    if (target == null) return null;
    return target.stolen != null
        ? VehicleInteraction.carjack
        : VehicleInteraction.enter;
  }

  /// Ближайшая машина в радиусе посадки: своя (текущая или брошенная) или
  /// машина потока, которую можно угнать.
  ({BuiltVehicle? own, StealableCar? stolen})? _nearestEnterable() {
    final playerPos = playerNode.globalTransform.getTranslation();
    BuiltVehicle? own;
    var ownDistance = vehicleInteractRadius;
    for (final car in [vehicle, ..._parkedPlayerCars]) {
      final distance =
          (car.node.globalTransform.getTranslation() - playerPos).length;
      if (distance <= ownDistance) {
        ownDistance = distance;
        own = car;
      }
    }
    final stolen = traffic.stealableNear(
      playerPos,
      radius: vehicleInteractRadius,
      maxSpeed: _carjackMaxSpeed,
    );
    if (stolen != null &&
        (own == null ||
            (stolen.car.position - playerPos).length < ownDistance)) {
      return (own: null, stolen: stolen);
    }
    return own == null ? null : (own: own, stolen: null);
  }

  /// Сесть в машину (свою или угнать из потока) / выйти — по ближайшей
  /// цели [vehicleInteraction]. Переключает и куда едет камера, и откуда
  /// читается джойстик (см. [GameModeState]).
  void toggleVehicle() {
    // The old touch control may disappear while held. Never carry its
    // throttle, sprint or fire state into the new control mode.
    inputState
      ..setMove(0, 0)
      ..isRunning = false
      ..handbrakeHeld = false
      ..fireHeld = false;
    inputState.aimHeld = false;
    inputState.consumeJump();
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
    _hookCrashSound(vehicle);
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
    final dents = traffic.deformationFor(car);
    traffic.removeCar(car);

    final built = buildVehicleWithSpec(
      stolen.look,
      vehicleSpecForModel(stolen.look.modelId) ?? _stolenCarSpec,
    );
    built.node
      ..position = car.position
      ..rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), car.heading);
    built.controller.heading = car.heading;
    built.inheritDeformation(dents);
    scene.add(built.node);

    _parkPlayerCar(vehicle);
    vehicle = built;

    final left = vm.Vector3(math.cos(car.heading), 0, -math.sin(car.heading));
    pedestrians.spawnFleeingDriver(
      car.position + left * 1.6,
      playerNode.globalTransform.getTranslation(),
    );
    wantedSystem.reportMinorCrime();
  }

  CharacterRayHit? _staticVehicleRaycast(
    vm.Vector3 origin,
    vm.Vector3 direction,
    double reach,
  ) {
    final end = origin + direction * reach;
    final box = vm.Aabb3.minMax(
      vm.Vector3(
        math.min(origin.x, end.x),
        math.min(origin.y, end.y),
        math.min(origin.z, end.z),
      ),
      vm.Vector3(
        math.max(origin.x, end.x),
        math.max(origin.y, end.y),
        math.max(origin.z, end.z),
      ),
    );
    final roots = <Node>[];
    districtStreamer.collectChunksOverlapping(box, roots);
    CharacterRayHit? nearest;
    for (final root in roots) {
      final hit = districtStreamer.castRoot(
        root,
        origin,
        direction,
        nearest?.distance ?? reach,
      );
      if (hit != null) nearest = hit;
    }
    return cityMap.castBarriers(
          origin,
          direction,
          nearest?.distance ?? reach,
        ) ??
        nearest;
  }

  /// Стволы и звук удара для машины игрока — поверх обработчика повреждений.
  void _hookCrashSound(BuiltVehicle car) {
    car.controller.extraHullSweep = (p, d, a, b, w, l) =>
        _vegetation?.sweepVehicleTrunks(p, d, a, b, w, l);
    if (!_crashHooked.add(car)) return;
    final field = CharacterCollisionField(
      districtStreamer: districtStreamer,
      probeRadiusMeters: 8,
      probeBelowMeters: 2,
      probeAboveMeters: 3,
      additionalRaycast: cityMap.castBarriers,
    );
    field.addColliderSource(
      () => [
        if (!identical(car, vehicle)) vehicle.node,
        for (final other in _parkedPlayerCars)
          if (!identical(car, other)) other.node,
        ..._decorCars,
        ...policeSystem.unitNodes,
        ...traffic.carNodes,
      ],
    );
    car.controller.contactBody = (source, point) {
      if (source is Node) {
        final controller = source.getComponent<VehicleControllerComponent>();
        if (controller != null && !identical(controller, car.controller)) {
          return controller.collisionBody(point);
        }
      }
      return traffic.collisionBody(source, point);
    };
    traffic.impactRaycast = _staticVehicleRaycast;
    car.controller
      ..groundHeightAt = terrain.heightAt
      ..obstacleRaycast = field.cast
      ..prepareObstacles = field.refresh;
    final previous = car.controller.onCollision;
    car.controller.onCollision = (impactSpeed) {
      previous?.call(impactSpeed);
      if (impactSpeed > 2.0) {
        audio.crash(car.node.globalTransform.getTranslation(), impactSpeed);
      }
    };
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
    final sunNode = _sunNode = Node()
      ..addComponent(DirectionalLightComponent(sunLight));
    // Компонент светит вдоль local +Z узла, поэтому направление задаётся
    // поворотом узла, а не полем DirectionalLight.direction.
    sunNode.lookAt(_sunLightDirection);
    return sunNode;
  }

  /// Неоновые вывески (включены на этапе детализации 16.10.2026).
  static const bool neonSignsEnabled = true;

  /// Неон — вывески из assets/data/neon_signs.json и мягкие пятна света от
  /// них (шейдер neon_glow.fmat). Не загрузился шейдер — вывески без пятен.
  Future<void> _buildNeon() async {
    final signs = await loadNeonSigns();
    Material? glow;
    try {
      glow = await loadFmatMaterial('assets/shaders/neon_glow.fmat');
    } catch (error) {
      // ignore: avoid_print
      print('Шейдер пятен неона не загрузился: $error');
    }
    final neon = _neon = await NeonSignsView.build(signs, glowMaterial: glow);
    scene.add(neon.buildNode());
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
    final characters = _characters;
    if (characters != null) {
      final model = _playerModel = characters.create(characters.roster.player);
      model.play(CharacterAnim.idle, fadeSeconds: 0);
      node.add(model.node);
      _playerMeshNode = model.node;
      return node;
    }

    const totalHeight = _playerCapsuleHeight + _playerCapsuleRadius * 2;
    final meshNode = Node(
      mesh: Mesh(
        CapsuleGeometry(
          radius: _playerCapsuleRadius,
          height: _playerCapsuleHeight,
        ),
        PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.82, 0.18, 0.18, 1.0),
      ),
    )..position = vm.Vector3(0, totalHeight / 2, 0);
    node.add(meshNode);
    _playerMeshNode = meshNode;
    return node;
  }

  /// Декоративные припаркованные машины у спавна — в них упираются
  /// персонаж и пули.
  final List<Node> _decorCars = [];
  final List<Node> _bulletCandidates = [];
  final vm.Aabb3 _bulletBox = vm.Aabb3();

  /// Луч пули против мира: чанки района вдоль луча и машины рядом с ним.
  /// Пешеходы — отдельно, аналитически (PedestrianSystem.raycastShootable).
  ///
  /// [includePolice] = false — без патрульных машин: офицер стоит вплотную
  /// к своей и стреляет мимо неё, иначе она закрывала бы ему обзор.
  double? _bulletRaycast(
    vm.Vector3 origin,
    vm.Vector3 direction,
    double maxDistance, {
    bool includePolice = true,
  }) {
    final end = origin + direction * maxDistance;
    _bulletBox
      ..min.setValues(
        math.min(origin.x, end.x),
        math.min(origin.y, end.y),
        math.min(origin.z, end.z),
      )
      ..max.setValues(
        math.max(origin.x, end.x),
        math.max(origin.y, end.y),
        math.max(origin.z, end.z),
      );
    _bulletCandidates.clear();
    districtStreamer.collectChunksOverlapping(_bulletBox, _bulletCandidates);
    final reachSq = (maxDistance + 4.0) * (maxDistance + 4.0);
    final cars = [
      vehicle.node,
      for (final car in _parkedPlayerCars) car.node,
      ..._decorCars,
      ...traffic.carNodes,
      if (includePolice) ...policeSystem.unitNodes,
    ];
    for (final car in cars) {
      if ((car.globalTransform.getTranslation() - origin).length2 <= reachSq) {
        _bulletCandidates.add(car);
      }
    }

    double? nearest;
    for (final root in _bulletCandidates) {
      final hit = districtStreamer.castRoot(
        root,
        origin,
        direction,
        nearest ?? maxDistance,
      );
      if (hit != null && (nearest == null || hit.distance < nearest)) {
        nearest = hit.distance;
      }
    }
    return nearest;
  }

  /// Оружие пешком: перезарядка, прицеливание (камера за плечо, корпус к
  /// прицелу) и выстрелы, пока зажата кнопка. За рулём не стреляем.
  void _updateWeapon(double deltaSeconds, {required bool isDriving}) {
    weapon.update(deltaSeconds);
    _weaponEffects.update(deltaSeconds);
    if (isDriving || isDead) {
      inputState.consumeReload();
      _aimHoldSeconds = 0.0;
      cameraController.aiming = false;
      _movement?.facingYawOverride = null;
      return;
    }

    if (inputState.consumeReload()) weapon.startReload();
    if (inputState.fireHeld) _aimHoldSeconds = _aimHoldAfterShot;
    _aimHoldSeconds = math.max(0.0, _aimHoldSeconds - deltaSeconds);
    final aiming =
        inputState.aimHeld || inputState.fireHeld || _aimHoldSeconds > 0.0;
    cameraController.aiming = aiming;
    _movement?.facingYawOverride = aiming ? cameraController.yaw : null;
    if (!inputState.fireHeld) return;

    // Ствол — у правой руки на уровне плеча, по курсу камеры (корпус
    // доворачивается к нему за доли секунды).
    final forward = cameraController.forward;
    final right = cameraController.right;
    final muzzle =
        playerNode.globalTransform.getTranslation() +
        vm.Vector3(0, 1.35, 0) +
        forward * 0.5 +
        right * 0.3;
    final shot = _shooting.tryFire(
      eye: cameraController.eyePosition,
      viewDirection: cameraController.viewDirection,
      muzzle: muzzle,
    );
    if (shot == null) return;
    _firedThisFrame = true;
    _weaponEffects.showShot(shot);
    audio.gunshot(shot.muzzle);
    for (final bullet in shot.bullets) {
      if (bullet.impact == BulletImpact.world) audio.bulletImpact(bullet.end);
    }
    wantedSystem.reportShooting(
      witnesses: shot.witnesses,
      wounded: shot.wounded,
      killed: shot.killed,
    );
    for (final kill in shot.kills) {
      _dropLoot(kill.feet, kill.kind);
    }
  }

  /// Клип модели игрока: убит — лежит, целится — оружие наизготовку
  /// (выстрел — отдача), иначе стоит/идёт/бежит по скорости. За рулём
  /// модель спрятана — не анимируется.
  void _updatePlayerModel(double deltaSeconds, {required bool isDriving}) {
    final model = _playerModel;
    if (model == null || isDriving) return;
    final speed = isDead ? 0.0 : (_movement?.horizontalSpeed ?? 0.0);
    final choice = locomotionAnim(
      speed: speed,
      lying: isDead,
      aiming: cameraController.aiming,
      previous: model.current,
    );
    if (_firedThisFrame && choice.anim == CharacterAnim.aim) {
      model.play(CharacterAnim.shoot, fadeSeconds: 0.05, restart: true);
    } else if (model.current != CharacterAnim.shoot ||
        model.currentFinished ||
        choice.anim != CharacterAnim.aim) {
      model.play(
        choice.anim,
        rate: choice.rate,
        fadeSeconds: isDead ? 0.12 : 0.2,
      );
    }
    model.update(deltaSeconds);
  }

  /// Добыча с убитого: деньги, а с полицейского ещё и патроны (иначе
  /// патроны кончались бы насовсем — магазинов пока нет).
  void _dropLoot(vm.Vector3 feet, TargetKind kind) {
    final drop = kind == TargetKind.officer
        ? _economy.officerDrop
        : _economy.pedestrianDrop;
    final money = drop.rollMoney(_random);
    if (money > 0) {
      _pickups.drop(
        Pickup(position: feet + vm.Vector3(0.4, 0, 0), money: money),
      );
    }
    if (drop.ammo > 0) {
      _pickups.drop(
        Pickup(
          position: feet + vm.Vector3(-0.4, 0, 0.3),
          money: 0,
          ammo: drop.ammo,
        ),
      );
    }
    if (drop.rollArmor(_random)) {
      _pickups.drop(
        Pickup(
          position: feet + vm.Vector3(0, 0, -0.5),
          money: 0,
          armor: drop.armor,
        ),
      );
    }
  }

  /// Добыча на земле: стареет, подбирается проходом рядом (пешком или на
  /// машине), мёртвый не подбирает.
  void _updatePickups(double deltaSeconds, vm.Vector3 trackedPosition) {
    final collected = _pickups.update(
      deltaSeconds,
      isDead ? null : trackedPosition,
    );
    for (final item in collected) {
      wallet.earn(item.money, TransactionReason.pickup);
      weapon.reserveAmmo += item.ammo;
      playerHealth.addArmor(item.armor.toDouble());
      audio.pickup();
    }
    _pickupsView.update(deltaSeconds);
    _propertyMarkers.update(deltaSeconds);
  }

  CityFixture? get nearbyBench {
    if (isDead ||
        gameModeState.mode != ControlMode.onFoot ||
        wantedState.stars > 0) {
      return null;
    }
    final p = playerNode.position;
    final found = cityMap.nearby('bench', p.x, p.z, radius: 2.5, limit: 1);
    return found.isEmpty ? null : found.first;
  }

  void restAtBench() {
    final bench = nearbyBench;
    if (bench == null) return;
    _restDamageRevision = playerHealth.damageRevision;
    benchRest.start(bench, playerNode.position);
  }

  /// Узел, за которым сейчас "следит" мир — игрок пешком или машина за
  /// рулём. Публичный, чтобы HUD мог показать координаты в debug-оверлее
  /// (см. GameView) без дублирования этой развилки по gameModeState.
  Node get trackedNode =>
      gameModeState.mode == ControlMode.driving ? vehicle.node : playerNode;

  /// Общая для всей игры логика тика (таймеры, спавн и т.д.), не привязанная
  /// к одному узлу. Per-node поведение живёт в компонентах, а не здесь.
  void Function()? onPerformanceScenarioChanged;
  bool _performanceValidated = false;
  late final performanceProbe = PerformanceProbe(this);

  // Developer benchmark only; never called in ordinary builds.
  void configurePerformanceScenario(String variant) {
    if (!_performanceValidated) {
      // ignore: avoid_print
      print(
        'PERF collision parity: ${districtStreamer.validateCollisionIndex()}',
      );
      _performanceValidated = true;
    }
    districtStreamer.indexedCollision = variant != 'legacy-drive';
    clock.hours = variant.startsWith('night') ? 23 : 13;
    clock.gameMinutesPerSecond = 0;
    scene.renderScale = variant == 'half-resolution' ? .5 : quality.renderScale;
    _sunLight?.castsShadow = variant != 'no-shadows' && quality.shadowsEnabled;
    if (variant == 'idle') {
      // ignore: avoid_print
      print(
        'PERF collision parity: ${districtStreamer.validateCollisionIndex()}',
      );
      return;
    }
    _hookCrashSound(vehicle);
    // Pick a clear starting stretch, retaining every traffic actor and
    // collision. Otherwise later phases can start directly behind a queue.
    var startZ = 42.0, best = -1.0;
    final trafficPositions = [
      ...traffic.carNodes,
      ..._decorCars,
      ...policeSystem.unitNodes,
    ].map((n) => n.globalTransform.getTranslation()).toList();
    for (final z in [42.0, 90.0, 140.0, 190.0, 240.0, 290.0, 340.0]) {
      var clearance = 200.0;
      for (final car in trafficPositions) {
        final ahead = car.z - z;
        if (ahead > -8 &&
            ahead < 200 &&
            (car.x - (_performanceRoadX(car.z) - 1.75)).abs() < 3) {
          clearance = math.min(clearance, math.max(0, ahead));
        }
      }
      if (clearance > best) {
        best = clearance;
        startZ = z;
      }
    }
    vehicle.node.position = vm.Vector3(
      _performanceRoadX(startZ) - 1.75,
      0,
      startZ,
    );
    vehicle.controller
      ..heading = .065
      ..velocityXZ.setZero();
    vehicle.controller.dynamics.stopYaw();
    gameModeState
      ..mode = ControlMode.driving
      ..activeVehicle = vehicle.controller;
    _playerMeshNode?.visible = false;
    cameraController.followTarget = vehicle.node;
    onPerformanceScenarioChanged?.call();
    cameraController.orbitBy(
      .065 - cameraController.yaw,
      .2 - cameraController.pitch,
    );
  }

  void finishPerformanceScenario() {
    inputState.setMove(0, 0);
    applyQuality(quality);
    clock.gameMinutesPerSecond = 1;
  }

  static const _performanceRoad = [
    (-72.95, 27.67),
    (-66.85, 116.7),
    (-61.28, 197.97),
    (-56.11, 266.78),
    (-52.36, 321.35),
    (-49.16, 373.11),
    (-45.13, 474.46),
    (-39.5, 544.63),
    (-36.36, 596.57),
    (-34.44, 623.73),
    (-29.48, 699.35),
    (-26.35, 746.89),
    (-24.03, 776.88),
    (-19.55, 801.49),
  ];
  double _performanceRoadX(double z) {
    for (var i = 1; i < _performanceRoad.length; i++) {
      final a = _performanceRoad[i - 1], b = _performanceRoad[i];
      if (z <= b.$2) {
        final t = ((z - a.$2) / (b.$2 - a.$2)).clamp(0.0, 1.0);
        return a.$1 + (b.$1 - a.$1) * t;
      }
    }
    return _performanceRoad.last.$1;
  }

  void setPerformanceThrottle() {
    // Keep the route running: arrest/death is covered by gameplay smoke,
    // not by this isolated driving/render comparison.
    wantedState.stars = 0;
    playerHealth.health = PlayerHealth.maxHealth;
    // Pure pursuit along the mapped Ilekskaya centreline, in its northbound
    // TrafficNetwork lane (rightOf(+Z) is -X in the current network). Straight throttle alone drifts into oncoming traffic as it bends.
    final p = vehicle.node.position;
    final targetZ = p.z + 15 + vehicle.controller.speed * .6;
    final targetX = _performanceRoadX(targetZ);
    final yaw = math.atan2(targetX - 1.75 - p.x, targetZ - p.z);
    final error =
        (yaw - vehicle.controller.heading + math.pi) % (2 * math.pi) - math.pi;
    inputState.setMove(
      (error * 4).clamp(-1, 1),
      vehicle.controller.speed > 22 ? .25 : 1,
    );
  }

  void tick(double deltaSeconds) {
    final trackedPosition = trackedNode.globalTransform.getTranslation();
    districtStreamer.updateAroundPosition(trackedPosition);
    final night = dayNight.lighting?.nightFactor ?? 0.0;
    if (streetLights.update(trackedPosition, night)) {
      _terrainView?.updateStreetLights(
        streetLights.selected.map((f) => f.groundLight).toList(),
        night,
      );
    }
    if (benchRest.update(
      deltaSeconds,
      trackedPosition,
      allowed:
          !isDead &&
          gameModeState.mode == ControlMode.onFoot &&
          wantedState.stars == 0 &&
          playerHealth.damageRevision == _restDamageRevision,
    )) {
      playerHealth.health = math.min(
        PlayerHealth.maxHealth,
        playerHealth.health + 20,
      );
    }

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

    _terrainView?.updateAround(trackedPosition);
    final isDriving = gameModeState.mode == ControlMode.driving;
    final viewForward = cameraController.forward;
    pedestrians
      ..viewPosition = cameraNode.globalTransform.getTranslation()
      ..viewForward = vm.Vector3(viewForward.x, 0, viewForward.z);
    final hits = pedestrians.update(
      deltaSeconds,
      trackedPosition,
      vehiclePosition: isDriving
          ? vehicle.node.globalTransform.getTranslation()
          : null,
      vehicleSpeed: isDriving ? vehicle.controller.speed : 0.0,
    );
    wantedSystem.update(
      deltaSeconds,
      pedestrianHits: hits,
      isSpeeding:
          isDriving && vehicle.controller.speed >= wantedSystem.speedThreshold,
    );

    _firedThisFrame = false;
    _sirenSeconds += deltaSeconds;
    VehicleModels.updateSirens(_sirenSeconds);
    // A retracted camera must not fill the screen with the player's head.
    // Separate hide/show thresholds prevent flicker along a wall edge.
    final playerMesh = _playerMeshNode;
    if (!isDriving && playerMesh != null) {
      final arm =
          (cameraController.eyePosition - cameraController.lookTarget).length;
      playerMesh.visible = arm > (playerMesh.visible ? 1.35 : 1.65);
    }
    _updateWeapon(deltaSeconds, isDriving: isDriving);
    _updatePlayerModel(deltaSeconds, isDriving: isDriving);
    _updateWeather(deltaSeconds);
    signals.advance(deltaSeconds);
    _signalsView.update();
    traffic.update(
      deltaSeconds,
      trackedPosition,
      external: _trafficObstacles(isDriving),
    );
    // Проезд на красный — только за рулём; детектор держит "в каком
    // перекрёстке был", поэтому зовётся каждый кадр, а пешком — с нулевой
    // скоростью (не нарушение, но зона перекрёстка обновляется).
    final ranRedLight = _redLightDetector.update(
      trackedPosition,
      isDriving ? vehicle.controller.velocityXZ : vm.Vector2.zero(),
    );
    if (ranRedLight) wantedSystem.reportMinorCrime();

    final caught = policeSystem.update(
      deltaSeconds,
      trackedPosition,
      blockers: traffic.carNodes.map(
        (node) => node.globalTransform.getTranslation(),
      ),
    );
    if (caught && !isDead) _handleArrest();
    _updateCombat(deltaSeconds, trackedPosition, isDriving: isDriving);
    _updatePickups(deltaSeconds, trackedPosition);
    _updateAudio(deltaSeconds, isDriving: isDriving);

    if (userIsAdjustingCamera) _cameraManualGrace = 1.5;
    _cameraManualGrace = math.max(0.0, _cameraManualGrace - deltaSeconds);
    if (isDriving &&
        _cameraManualGrace == 0.0 &&
        vehicle.controller.speed > 1.0) {
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
    dayNight.update(
      deltaSeconds,
      weather: params,
      lightningFlash: _weatherView.lightningFlash,
    );
    _weatherView.update(
      deltaSeconds,
      dayNight.lighting!,
      params,
      cameraNode.globalTransform.getTranslation(),
    );
    weather.update(
      deltaSeconds,
      gameHoursPassed: deltaSeconds * clock.gameMinutesPerSecond / 60.0,
      dayOfYear: clock.dayOfYear,
    );
    _vegetation?.setSnowCover(params.snowCover);
    _wetRoads.update(params.wetness);
    _facades.wetness = params.wetness;
    final lighting = dayNight.lighting!;
    _neon?.update(
      deltaSeconds,
      nightFactor: lighting.nightFactor,
      goldenHour: lighting.goldenHour,
    );
  }

  /// То, перед чем тормозит трафик помимо друг друга: игрок (пешком или
  /// его машина), полиция, пешеходы. Радиусы — полуширины в плане.
  Iterable<TrafficObstacle> _trafficObstacles(bool isDriving) sync* {
    if (isDriving) {
      yield (
        position: vehicle.node.globalTransform.getTranslation(),
        radius: 1.0,
      );
    } else {
      yield (
        position: playerNode.globalTransform.getTranslation(),
        radius: _playerCapsuleRadius,
      );
      // Пустая машина игрока тоже стоит где-то — возможно, посреди дороги.
      yield (
        position: vehicle.node.globalTransform.getTranslation(),
        radius: 1.0,
      );
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
    for (final position in policeSystem.officers.alivePositions) {
      yield (position: position, radius: PedestrianSystem.bodyRadius);
    }
  }

  /// Игрока поймали (см. PoliceSystem.update) — розыск сбрасывается,
  /// патрульные машины исчезают сразу (как в GTA на экране "задержан", не
  /// постепенно), игрок телепортируется к точке спавна (условная
  /// "безопасная точка" — отдельного полицейского участка на карте пока
  /// нет). HUD показывает баннер через ArrestState (см. arrest_banner.dart).
  void _updateAudio(double deltaSeconds, {required bool isDriving}) {
    if (weapon.isReloading && !_wasReloading) {
      audio.reload(playerNode.globalTransform.getTranslation());
    }
    _wasReloading = weapon.isReloading;
    final params = weather.params;
    audio.update(
      deltaSeconds,
      playerFeet: playerNode.globalTransform.getTranslation(),
      playerSpeed: isDead ? 0.0 : (_movement?.horizontalSpeed ?? 0.0),
      playerGrounded: _movement?.isGrounded ?? true,
      vehicle: isDriving
          ? (
              position: vehicle.node.globalTransform.getTranslation(),
              speed: vehicle.controller.speed,
              maxSpeed: vehicle.controller.maxSpeed,
              driftFactor: vehicle.controller.driftFactor,
            )
          : null,
      rain: params.rain,
      snow: params.snow,
      wind: params.wind,
      nightFactor: dayNight.lighting?.nightFactor ?? 0.0,
      lightningFlash: _weatherView.lightningFlash,
      policeCars: policeSystem.unitNodes,
    );
  }

  /// Полиция стреляет по игроку, здоровье, смерть и возрождение.
  void _updateCombat(
    double deltaSeconds,
    vm.Vector3 trackedPosition, {
    required bool isDriving,
  }) {
    playerHealth.update(deltaSeconds);
    if (isDead) {
      _deathSeconds -= deltaSeconds;
      if (_deathSeconds <= 0.0) _respawnAfterDeath();
      return;
    }

    final speed = isDriving
        ? vehicle.controller.speed
        : (_movement?.horizontalSpeed ?? 0.0);
    final shots = policeSystem.officers.update(
      deltaSeconds,
      trackedPosition,
      playerSpeed: speed,
      playerInVehicle: isDriving,
      lineOfSight: (from, to) {
        final delta = to - from;
        final distance = delta.length;
        // Чуть недотягиваем: сама цель (машина игрока) — тоже препятствие.
        return _bulletRaycast(
              from,
              delta / distance,
              math.max(0.0, distance - 2.5),
              includePolice: false,
            ) ==
            null;
      },
      // Путь на уровне колен и груди: низкий забор тоже преграда.
      pathClear: (from, direction, distance) =>
          _bulletRaycast(from + vm.Vector3(0, 0.5, 0), direction, distance) ==
              null &&
          _bulletRaycast(from + vm.Vector3(0, 1.2, 0), direction, distance) ==
              null,
    );
    for (final shot in shots) {
      _weaponEffects.showShot(
        ShotOutcome(
          muzzle: shot.muzzle,
          bullets: [
            BulletTrace(
              shot.end,
              shot.hit ? BulletImpact.flesh : BulletImpact.none,
            ),
          ],
          wounded: 0,
          killed: 0,
          witnesses: 0,
        ),
      );
      audio.gunshot(shot.muzzle, police: true);
      if (!shot.hit) continue;
      audio.hurt();
      // Кузов закрывает от половины пуль.
      final damage = OfficerTuning.damage * (isDriving ? 0.5 : 1.0);
      if (playerHealth.takeDamage(damage)) {
        _handleDeath();
        return;
      }
    }
  }

  /// Игрок убит: выходит из машины, падает и лежит, потом возрождается.
  void _handleDeath() {
    inputState.fireHeld = false;
    if (gameModeState.mode == ControlMode.driving) toggleVehicle();
    _deathSeconds = _deathLieSeconds;
    deathState.trigger();
    audio.wasted();
    _setPlayerLying(true);
  }

  void _respawnAfterDeath() {
    _deathSeconds = 0.0;
    // "Больница" — лечение не бесплатное.
    wallet.charge(
      _economy.hospital.amountFor(wallet.balance),
      TransactionReason.hospital,
    );
    playerHealth.reset();
    wantedState.stars = 0;
    policeSystem.clearUnits();
    _setPlayerLying(false);
    _movement?.teleport(_respawnPosition);
    cameraController.followTarget = playerNode;
  }

  /// Для радара и компаса: курс камеры (экран "вверх" — её взгляд).
  double get cameraYaw => cameraController.yaw;

  /// Курс игрока или его машины — стрелка в центре радара.
  double get playerHeading => gameModeState.mode == ControlMode.driving
      ? vehicle.controller.heading
      : (_movement?.motion.yaw ?? 0.0);

  /// Скорость — радар отдаляется на ходу.
  double get playerSpeed => gameModeState.mode == ControlMode.driving
      ? vehicle.controller.speed
      : (_movement?.horizontalSpeed ?? 0.0);

  /// Метки для радара/компаса: дома, полиция, добыча.
  void collectBlips(List<HudBlip> out) {
    for (final property in properties.properties) {
      final kind = properties.isOwned(property)
          ? BlipKind.houseOwned
          : BlipKind.houseForSale;
      out.add(HudBlip(kind, property.entryPoint.x, property.entryPoint.z));
    }
    for (final car in policeSystem.unitNodes) {
      final p = car.globalTransform.getTranslation();
      out.add(HudBlip(BlipKind.policeCar, p.x, p.z));
    }
    for (final p in policeSystem.officers.alivePositions) {
      out.add(HudBlip(BlipKind.officer, p.x, p.z));
    }
    for (final item in _pickups.items) {
      final kind = item.money > 0
          ? BlipKind.money
          : (item.armor > 0 ? BlipKind.armor : BlipKind.ammo);
      out.add(HudBlip(kind, item.position.x, item.position.z));
    }
  }

  /// Где появляется игрок после смерти и ареста: у своего дома, если он
  /// куплен, иначе на точке спавна.
  vm.Vector3 get _respawnPosition =>
      properties.respawnPoint() ?? worldConfig.playerSpawnPosition;

  /// Что можно сделать у входа в дом прямо сейчас (для кнопки в HUD):
  /// только пешком и живым.
  PropertyInteraction? get propertyInteraction {
    if (isDead || gameModeState.mode != ControlMode.onFoot) return null;
    return properties.interactionAt(
      playerNode.globalTransform.getTranslation(),
      wallet,
      wanted: wantedState.stars > 0,
    );
  }

  /// Купить дом, у входа в который стоит игрок. true — куплен.
  bool buyNearbyProperty() {
    final interaction = propertyInteraction;
    if (interaction == null || interaction.owned) return false;
    final bought = properties.buy(interaction.property, wallet);
    if (bought) audio.purchase();
    // Покупку не должен отменить вылет игры — сразу автосохранение.
    if (bought) saveGame();
    return bought;
  }

  /// Капсула игрока лежит на земле (убит) или стоит.
  void _setPlayerLying(bool lying) {
    final mesh = _playerMeshNode;
    // Модель падает клипом смерти (см. _updatePlayerModel).
    if (mesh == null || _playerModel != null) return;
    const totalHeight = _playerCapsuleHeight + _playerCapsuleRadius * 2;
    mesh.localTransform = lying
        ? vm.Matrix4.compose(
            vm.Vector3(0, _playerCapsuleRadius, 0),
            vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
            vm.Vector3.all(1.0),
          )
        : vm.Matrix4.translation(vm.Vector3(0, totalHeight / 2, 0));
  }

  void _handleArrest() {
    audio.busted();
    wallet.charge(
      _economy.arrest.amountFor(wallet.balance),
      TransactionReason.arrestFine,
    );
    wantedState.stars = 0;
    policeSystem.clearUnits();
    arrestState.trigger();
    if (gameModeState.mode == ControlMode.driving) toggleVehicle();
    playerNode.position = _respawnPosition;
    cameraController.followTarget = playerNode;
  }

  /// Дистанция камеры за игроком в обычном положении.
  static const double _cameraDistance = 6.0;

  /// Restrict camera rays to chunks along the arm, rather than walking the
  /// whole scene (including animated people and decorative vegetation).
  double? _castCameraObstruction(
    vm.Vector3 origin,
    vm.Vector3 direction,
    double reach,
  ) {
    final end = origin + direction * reach;
    final bounds = vm.Aabb3.minMax(
      vm.Vector3(
        math.min(origin.x, end.x) - 0.3,
        math.min(origin.y, end.y) - 0.3,
        math.min(origin.z, end.z) - 0.3,
      ),
      vm.Vector3(
        math.max(origin.x, end.x) + 0.3,
        math.max(origin.y, end.y) + 0.3,
        math.max(origin.z, end.z) + 0.3,
      ),
    );
    final roots = <Node>[];
    districtStreamer.collectChunksOverlapping(bounds, roots);
    double? nearest;
    for (final root in roots) {
      final hit = districtStreamer.castRoot(
        root,
        origin,
        direction,
        nearest ?? reach,
      );
      if (hit != null) nearest = hit.distance;
    }
    final fence = cityMap.castBarriers(origin, direction, nearest ?? reach);
    if (fence != null) nearest = fence.distance;
    return terrain.cast(origin, direction, nearest ?? reach) ?? nearest;
  }

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
    cameraController.distance = math.min(
      _cameraDistance,
      clearance / math.sin(-pitch),
    );
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
