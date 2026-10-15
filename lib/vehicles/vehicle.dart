import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'vehicle_controller_component.dart';
import 'vehicle_damage.dart';
import 'vehicle_input_bridge_component.dart';
import 'vehicle_models.dart';
import 'vehicle_spec.dart';

/// Габариты одного силуэта машины — общие для всех архетипов
/// (см. [VehicleArchetype]), чтобы не дублировать сборку кузова/колёс на
/// каждый новый тип.
class VehicleDimensions {
  VehicleDimensions({
    required this.bodyWidth,
    required this.chassisHeight,
    required this.bodyLength,
    required this.cabinHeight,
    required this.cabinLength,
    required this.cabinWidth,
    required this.cabinZOffset,
    required this.wheelRadius,
    required this.wheelWidth,
    required this.paintColor,
    this.modelId,
  });

  /// Модель из assets/models/vehicles (см. [VehicleModels]); без неё или
  /// пока модели не загружены — процедурная сборка из кубов. Габариты выше
  /// у машин с моделью сняты с самой модели (prepare_vehicles.mjs) — по ним
  /// считаются столкновения.
  final String? modelId;

  final double bodyWidth;
  final double chassisHeight;
  final double bodyLength;
  final double cabinHeight;
  final double cabinLength;
  final double cabinWidth;

  /// Смещение кабины по Z от центра кузова — отрицательное к корме
  /// (силуэт седана/хэтчбека), положительное к носу (кабина
  /// впереди, кузов сзади).
  final double cabinZOffset;
  final double wheelRadius;
  final double wheelWidth;
  final vm.Vector4 paintColor;

  /// Тот же силуэт другого цвета — для разноцветного трафика.
  VehicleDimensions withPaint(vm.Vector4 color) => VehicleDimensions(
    bodyWidth: bodyWidth,
    chassisHeight: chassisHeight,
    bodyLength: bodyLength,
    cabinHeight: cabinHeight,
    cabinLength: cabinLength,
    cabinWidth: cabinWidth,
    cabinZOffset: cabinZOffset,
    wheelRadius: wheelRadius,
    wheelWidth: wheelWidth,
    paintColor: color,
    modelId: modelId,
  );
}

/// Готовые типы машин. Габариты кузова и колёс — с моделей (см.
/// tools/assets/prepare_vehicles.mjs), высоты кабины — для процедурной
/// сборки на случай, когда моделей нет (тесты).
class VehicleArchetype {
  static final sedan = VehicleDimensions(
    bodyWidth: 1.81,
    chassisHeight: 0.6,
    bodyLength: 4.22,
    cabinHeight: 0.55,
    cabinLength: 2.2,
    cabinWidth: 1.81 * 0.86,
    cabinZOffset: -0.35, // сдвиг кабины к корме — силуэт седана
    wheelRadius: 0.262,
    wheelWidth: 0.22,
    paintColor: vm.Vector4(0.12, 0.32, 0.62, 1.0), // синий
    modelId: 'sedan',
  );

  static final hatchback = VehicleDimensions(
    bodyWidth: 1.64,
    chassisHeight: 0.55,
    bodyLength: 3.31, // короче седана — компактный городской силуэт
    cabinHeight: 0.55,
    cabinLength: 2.0,
    cabinWidth: 1.64 * 0.85,
    cabinZOffset: -0.15,
    wheelRadius: 0.248,
    wheelWidth: 0.20,
    paintColor: vm.Vector4(0.75, 0.15, 0.12, 1.0), // красный
    modelId: 'hatchback',
  );

  static final suv = VehicleDimensions(
    bodyWidth: 2.11,
    chassisHeight: 0.75,
    bodyLength: 4.21,
    cabinHeight: 0.65,
    cabinLength: 2.4,
    cabinWidth: 2.11 * 0.86,
    cabinZOffset: -0.2,
    wheelRadius: 0.327,
    wheelWidth: 0.26,
    paintColor: vm.Vector4(0.35, 0.36, 0.34, 1.0), // защитный хаки
    modelId: 'suv',
  );

  static final sports = VehicleDimensions(
    bodyWidth: 1.87,
    chassisHeight: 0.5,
    bodyLength: 3.93,
    cabinHeight: 0.5,
    cabinLength: 1.8,
    cabinWidth: 1.87 * 0.8,
    cabinZOffset: -0.3,
    wheelRadius: 0.28,
    wheelWidth: 0.24,
    paintColor: vm.Vector4(0.85, 0.85, 0.88, 1.0),
    modelId: 'sports',
  );

  static final sports2 = VehicleDimensions(
    bodyWidth: 1.81,
    chassisHeight: 0.5,
    bodyLength: 3.97,
    cabinHeight: 0.5,
    cabinLength: 1.8,
    cabinWidth: 1.81 * 0.8,
    cabinZOffset: -0.3,
    wheelRadius: 0.26,
    wheelWidth: 0.24,
    paintColor: vm.Vector4(0.9, 0.4, 0.05, 1.0), // оранжевый
    modelId: 'sports2',
  );

  /// Такси — цвет фирменный, перекраска (withPaint) на модели не действует.
  static final taxi = VehicleDimensions(
    bodyWidth: 1.81,
    chassisHeight: 0.6,
    bodyLength: 4.22,
    cabinHeight: 0.55,
    cabinLength: 2.2,
    cabinWidth: 1.81 * 0.86,
    cabinZOffset: -0.35,
    wheelRadius: 0.262,
    wheelWidth: 0.22,
    paintColor: vm.Vector4(0.95, 0.75, 0.05, 1.0), // жёлтый
    modelId: 'taxi',
  );

  /// Мигалка у модели своя (материалы Siren_*, мигают через
  /// VehicleModels.updateSirens); без модели полицейская система ставит
  /// светобалку сама (см. lib/police/police_system.dart).
  static final police = VehicleDimensions(
    bodyWidth: 1.78,
    chassisHeight: 0.6,
    bodyLength: 3.73,
    cabinHeight: 0.55,
    cabinLength: 2.0,
    cabinWidth: 1.78 * 0.86,
    cabinZOffset: -0.3,
    wheelRadius: 0.275,
    wheelWidth: 0.22,
    paintColor: vm.Vector4(0.92, 0.92, 0.94, 1.0), // белый кузов
    modelId: 'police',
  );

  /// Машины с моделью для трафика (полиция — отдельно).
  static List<VehicleDimensions> get civilian => [sedan, hatchback, suv, sports, sports2, taxi];
}

/// Процедурный плейсхолдер машины — низкий кузов + кабина сверху (сдвиг
/// кабины и наличие грузового отсека определяются [VehicleDimensions],
/// см. [VehicleArchetype] для готовых силуэтов) + 4 колеса + фары.
/// Настоящие 3D-модели — отдельная задача, здесь только геометрия на время
/// их отсутствия. Разгон/торможение/руление заданы в assets/data/vehicles.json
/// (car_sedan_01, но код его пока не читает, числа синхронизированы вручную
/// — см. PROGRESS.md) — здесь только геометрия.
///
/// Три визуальных состояния кузова (см. [DamageLevel]) — не настоящая
/// деформация, а переключение видимости между тремя заранее построенными
/// preset-узлами (pristine/damaged/wrecked), как и было задумано в
/// PROGRESS.md (полноценная деформация ждёт rigid-body физики — см. решение
/// про flutter_scene_rapier там же).
class BuiltVehicle {
  BuiltVehicle({
    required this.node,
    required this.controller,
    required this.damage,
    required Map<DamageLevel, Node> bodyVariants,
  }) : _bodyVariants = bodyVariants {
    _syncVisibility();
    controller.onCollision = (impactSpeed) {
      damage.registerCollision(impactSpeed);
      _syncVisibility();
    };
  }

  /// Узел-машина — точка контакта с землёй (как и у игрока), тот же паттерн:
  /// origin на уровне земли, меши смещены вверх дочерними узлами.
  final Node node;
  final VehicleControllerComponent controller;
  final VehicleDamageState damage;
  final Map<DamageLevel, Node> _bodyVariants;

  DamageLevel? _visibleLevel;

  void _syncVisibility() {
    final level = damage.level;
    if (level == _visibleLevel) return;
    for (final entry in _bodyVariants.entries) {
      entry.value.visible = entry.key == level;
    }
    _visibleLevel = level;
  }
}

Future<BuiltVehicle> buildPlaceholderSedan() =>
    buildVehicle(VehicleArchetype.sedan, vehicleId: 'car_sedan_01');

/// Запасные числа вождения — если [vehicleId] не задан или записи с таким
/// id нет в assets/data/vehicles.json (сейчас там есть только car_sedan_01
/// — у остальных типов своих записей ещё нет, они пока decorative-only и
/// вообще не проезжают через VehicleControllerComponent).
const fallbackVehicleSpec = VehicleSpec(
  maxSpeedKmh: 200.0, // было 165 — см. PROGRESS.md
  acceleration: 16.0, // было 8.2 — разгон ощущался вялым
  braking: 32.0, // было 10.5 — торможение тянулось неприлично долго
);

/// Собирает управляемую машину — с контроллером вождения и системой
/// повреждений (см. [BuiltVehicle]). Для декоративных припаркованных машин
/// без физики/повреждений см. [buildStaticVehicleVisual]. Числа
/// разгона/торможения/скорости — из assets/data/vehicles.json по
/// [vehicleId], либо [fallbackVehicleSpec], если записи нет. [attachPlayerInput]
/// выключается для AI-машин (см. [buildVehicleWithSpec]) — иначе они бы
/// получали тот же джойстик, что и машина игрока.
Future<BuiltVehicle> buildVehicle(
  VehicleDimensions dims, {
  String? vehicleId,
  bool attachPlayerInput = true,
}) async {
  final spec = (vehicleId != null ? await loadVehicleSpec(vehicleId) : null) ?? fallbackVehicleSpec;
  return buildVehicleWithSpec(dims, spec, attachPlayerInput: attachPlayerInput);
}

/// Синхронное ядро [buildVehicle] — без чтения JSON. Нужно
/// PoliceSystem-у: спавн патрульной машины происходит посреди
/// Game.tick() (синхронного), а не в load(), поэтому спека загружается
/// один раз заранее (см. PoliceSystem.create), а сама сборка узла —
/// синхронная, чтобы не растягивать спавн на несколько кадров.
/// [attachPlayerInput] = false для AI-машин — их вход
/// (throttle/steer) пишет AI, а не VehicleInputBridgeComponent
/// (который иначе слушал бы джойстик игрока независимо от того, в какую
/// машину он сейчас сел).
BuiltVehicle buildVehicleWithSpec(
  VehicleDimensions dims,
  VehicleSpec spec, {
  bool attachPlayerInput = true,
}) {
  final node = Node();

  final bodyVariants = {
    for (final level in DamageLevel.values) level: _buildBodyVariant(level, dims),
  };
  bodyVariants.values.forEach(node.add);
  _addWheels(node, dims);

  final controller = VehicleControllerComponent(
    maxSpeed: spec.maxSpeedMs,
    acceleration: spec.acceleration,
    braking: spec.braking,
    groundPlaneHeight: 0.0,
    bodyHalfWidth: dims.bodyWidth / 2,
    bodyHalfLength: dims.bodyLength / 2,
  );
  node.addComponent(controller);
  if (attachPlayerInput) node.addComponent(VehicleInputBridgeComponent(controller));

  return BuiltVehicle(
    node: node,
    controller: controller,
    damage: VehicleDamageState(),
    bodyVariants: bodyVariants,
  );
}

/// Общий материал целых фар всех машин (лениво — материалы создаются
/// только после инициализации движка).
PhysicallyBasedMaterial get _headlightMaterial => VehicleModels.headlightMaterial;

const double _headlightDayStrength = 2.0;
const double _headlightNightStrength = 9.0;

/// Фары всех машин: днём тускло светятся, ночью горят (с bloom — ореол).
/// [nightFactor] 0..1 из суточного цикла (lib/time/).
void setHeadlightsGlow(double nightFactor) {
  _headlightMaterial.emissiveStrength =
      _headlightDayStrength + (_headlightNightStrength - _headlightDayStrength) * nightFactor;
  // Габариты сзади ночью горят заметно, днём едва тлеют.
  VehicleModels.tailLightMaterial.emissiveStrength = 0.6 + 3.4 * nightFactor;
}

/// Чисто декоративная машина (без контроллера/повреждений) — для "фонового"
/// транспорта, припаркованного вдоль улиц (см. Game.load()). Всегда в
/// исходном (pristine) виде — повреждать её нечем, раз она не участвует в
/// столкновениях.
Node buildStaticVehicleVisual(VehicleDimensions dims) {
  final node = _buildBodyVariant(DamageLevel.pristine, dims);
  _addWheels(node, dims);
  return node;
}

void _addWheels(Node node, VehicleDimensions dims) {
  final models = VehicleModels.instance;
  final modelId = dims.modelId;
  if (models != null && modelId != null && models.has(modelId)) {
    final wheels = models.wheels(modelId);
    wheels.forEach(node.add);
    final wheelbase = wheels.length == 3 ? (wheels[0].position.z - wheels[2].position.z).abs() : 2.5;
    node.addComponent(WheelSpinComponent(wheels, wheelRadius: dims.wheelRadius, wheelbase: wheelbase));
    return;
  }
  final wheelMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.05, 0.05, 0.05, 1.0)
    ..roughnessFactor = 0.9;
  final wheelRotation = vm.Quaternion.axisAngle(vm.Vector3(0, 0, 1), math.pi / 2);

  final wheelOffsets = [
    vm.Vector3(dims.bodyWidth / 2, dims.wheelRadius, dims.bodyLength / 2 - dims.wheelRadius * 1.4),
    vm.Vector3(-dims.bodyWidth / 2, dims.wheelRadius, dims.bodyLength / 2 - dims.wheelRadius * 1.4),
    vm.Vector3(dims.bodyWidth / 2, dims.wheelRadius, -dims.bodyLength / 2 + dims.wheelRadius * 1.4),
    vm.Vector3(-dims.bodyWidth / 2, dims.wheelRadius, -dims.bodyLength / 2 + dims.wheelRadius * 1.4),
  ];
  for (final offset in wheelOffsets) {
    final wheel = Node(
      mesh: Mesh(
        CylinderGeometry(bottomRadius: dims.wheelRadius, topRadius: dims.wheelRadius, height: dims.wheelWidth),
        wheelMaterial,
      ),
    )
      ..position = offset
      ..rotation = wheelRotation;
    node.add(wheel);
  }
}

/// Кузов под один [DamageLevel] — из модели или из кубов. Колёса не
/// варьируются по повреждениям — строятся отдельно в [_addWheels].
Node _buildBodyVariant(DamageLevel level, VehicleDimensions dims) {
  final models = VehicleModels.instance;
  final modelId = dims.modelId;
  if (models != null && modelId != null && models.has(modelId)) {
    return models.body(modelId, level, dims.paintColor);
  }
  final variant = Node();

  // У pristine — паспортный цвет архетипа; damaged/wrecked одинаково темнее
  // и грязнее вне зависимости от исходного цвета — иначе пришлось бы
  // подбирать "грязную версию" под каждый новый цвет вручную.
  final paintColor = switch (level) {
    DamageLevel.pristine => dims.paintColor,
    DamageLevel.damaged => vm.Vector4(
      dims.paintColor.x * 0.6,
      dims.paintColor.y * 0.6,
      dims.paintColor.z * 0.6,
      1.0,
    ),
    DamageLevel.wrecked => vm.Vector4(0.05, 0.05, 0.05, 1.0), // копоть/ржавчина
  };
  final paintMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = paintColor
    ..metallicFactor = level == DamageLevel.wrecked ? 0.1 : 0.6
    ..roughnessFactor = switch (level) {
      DamageLevel.pristine => 0.35,
      DamageLevel.damaged => 0.55,
      DamageLevel.wrecked => 0.8,
    };

  final chassis = Node(
    mesh: Mesh(
      CuboidGeometry(vm.Vector3(dims.bodyWidth, dims.chassisHeight, dims.bodyLength)),
      paintMaterial,
    ),
  )..position = vm.Vector3(0, dims.wheelRadius + dims.chassisHeight / 2, 0);
  variant.add(chassis);

  // Кабина: у wrecked стекло-материал светлее и матовее — "разбитое"
  // вместо чистого тонированного стекла у pristine/damaged.
  final cabinColor = level == DamageLevel.wrecked
      ? vm.Vector4(0.35, 0.35, 0.38, 1.0)
      : vm.Vector4(0.05, 0.06, 0.08, 1.0);
  final cabinMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = cabinColor
    ..metallicFactor = 0.1
    ..roughnessFactor = level == DamageLevel.wrecked ? 0.6 : 0.15;
  final cabin = Node(
    mesh: Mesh(
      CuboidGeometry(vm.Vector3(dims.cabinWidth, dims.cabinHeight, dims.cabinLength)),
      cabinMaterial,
    ),
  )..position = vm.Vector3(
      0,
      dims.wheelRadius + dims.chassisHeight + dims.cabinHeight / 2,
      dims.cabinZOffset,
    );
  variant.add(cabin);

  // Фары: damaged — левая разбита, wrecked — обе. Целые — общий на весь
  // город материал, чтобы ночью включать фары всем машинам одной правкой
  // (см. setHeadlightsGlow).
  final workingHeadlightMaterial = _headlightMaterial;
  final brokenHeadlightMaterial = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.25, 0.25, 0.25, 1.0)
    ..roughnessFactor = 0.9;
  const headlightSize = 0.14;
  for (final side in [-1, 1]) {
    final broken = level == DamageLevel.wrecked || (level == DamageLevel.damaged && side < 0);
    final headlight = Node(
      mesh: Mesh(
        CuboidGeometry(vm.Vector3(headlightSize, headlightSize, 0.05)),
        broken ? brokenHeadlightMaterial : workingHeadlightMaterial,
      ),
    )..position = vm.Vector3(
        side * (dims.bodyWidth / 2 - headlightSize),
        dims.wheelRadius + dims.chassisHeight / 2,
        dims.bodyLength / 2,
      );
    variant.add(headlight);
  }

  // Смятый бампер — тёмный кубик поверх переднего края, крупнее у wrecked.
  // Не настоящая деформация меша (см. doc-комментарий класса), но читается
  // как урон при взгляде на машину, а не только по смене цвета краски.
  if (level != DamageLevel.pristine) {
    final crumpleSize = level == DamageLevel.wrecked ? 0.5 : 0.25;
    final crumpleMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.08, 0.08, 0.08, 1.0)
      ..roughnessFactor = 0.95;
    final crumple = Node(
      mesh: Mesh(
        CuboidGeometry(vm.Vector3(dims.bodyWidth * 0.9, dims.chassisHeight * 0.7, crumpleSize)),
        crumpleMaterial,
      ),
    )..position = vm.Vector3(
        0,
        dims.wheelRadius + dims.chassisHeight / 2,
        dims.bodyLength / 2 - crumpleSize / 2,
      );
    variant.add(crumple);
  }

  return variant;
}
