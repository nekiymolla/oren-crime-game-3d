import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'day_night.dart';

/// Применяет [GameClock] к сцене: солнце/луна, цвет неба, освещение от
/// неба, светящиеся ночью окна и фары. Логика (где солнце, какого цвета
/// небо) — в day_night.dart и проверена тестами; здесь только перенос
/// чисел в объекты движка.
class DayNightView {
  DayNightView({
    required this.scene,
    required this.clock,
    required this.sunNode,
    required this.sunLight,
    required this.sky,
    required this.shadowsAllowed,
    this.onNightFactor,
    this.unlitSurfaces = const [],
  });

  final Scene scene;
  final GameClock clock;
  final Node sunNode;
  final DirectionalLight sunLight;
  final GradientSkySource sky;

  /// Тени разрешены пресетом/debug-панелью — ночью их всё равно нет.
  final bool Function() shadowsAllowed;

  /// Для систем со своим "ночным" видом (фары машин).
  final void Function(double nightFactor)? onNightFactor;

  /// Unlit-поверхности (плейсхолдер-земля) — свет на них не действует,
  /// поэтому их цвет затемняется вручную (см. SkyLighting.unlitTint).
  final List<UnlitMaterial> unlitSurfaces;
  late final List<vm.Vector4> _unlitDayColors = [for (final m in unlitSurfaces) m.baseColorFactor.clone()];

  /// Материалы окон из чанков района (помечены пайплайном
  /// mark_night_materials.mjs: emissive-текстура при нулевой яркости).
  final List<PhysicallyBasedMaterial> _glowMaterials = [];
  final Set<PhysicallyBasedMaterial> _known = {};

  vm.Vector3? _appliedLightDirection;
  double _appliedGlow = -1.0;
  SkyLighting? _last;

  /// Направление света меняем ступеньками не мельче этого угла: при каждой
  /// смене направления движок перестраивает кэш теней неподвижных объектов
  /// (деревья, дома — на слабом Android их тени стоили 46 мс без кэша),
  /// а полградуса раз в ~2 игровые минуты глазом не видно.
  static final double _directionStepCos = math.cos(0.5 * math.pi / 180);

  /// Тёплый свет окон ночью (умножается на рисунок окон из текстуры).
  static final vm.Vector4 _windowGlow = vm.Vector4(1.0, 0.78, 0.45, 1.0);
  static const double _windowGlowStrength = 2.2;

  SkyLighting? get lighting => _last;

  /// Чанк района загружен — находим в нём ночные материалы.
  void registerChunk(Node chunk) {
    for (final meshNode in chunk.meshNodes) {
      for (final primitive in meshNode.mesh!.primitives) {
        final material = primitive.material;
        if (material is! PhysicallyBasedMaterial || material.emissiveTexture == null) continue;
        if (!_known.add(material)) continue;
        _glowMaterials.add(material);
        _applyGlow(material, math.max(_appliedGlow, 0.0));
      }
    }
  }

  void update(double deltaSeconds) {
    clock.advance(deltaSeconds);
    final lighting = _last = evaluateSky(clock.hours, clock.dayOfYear);

    sky
      ..zenithColor = lighting.zenithColor
      ..horizonColor = lighting.horizonColor
      ..groundColor = lighting.groundColor
      ..sunDirection = sunDirection(clock.hours, clock.dayOfYear)
      ..sunColor = lighting.sunDiskColor;
    scene.environmentIntensity = lighting.environmentIntensity;
    final tint = lighting.unlitTint;
    for (var i = 0; i < unlitSurfaces.length; i++) {
      final day = _unlitDayColors[i];
      unlitSurfaces[i].baseColorFactor = vm.Vector4(day.x * tint.x, day.y * tint.y, day.z * tint.z, day.w);
    }

    sunLight
      ..color = lighting.lightColor
      ..intensity = lighting.lightIntensity
      ..castsShadow = shadowsAllowed() && lighting.castsShadow;

    final applied = _appliedLightDirection;
    if (applied == null || applied.dot(lighting.lightDirection) < _directionStepCos) {
      _appliedLightDirection = lighting.lightDirection.clone();
      // Компонент светит вдоль local +Z узла: смотрим ОТ источника к земле.
      sunNode.lookAt(-lighting.lightDirection);
    }

    final glow = lighting.nightFactor;
    if ((glow - _appliedGlow).abs() > 0.01) {
      _appliedGlow = glow;
      for (final material in _glowMaterials) {
        _applyGlow(material, glow);
      }
      onNightFactor?.call(glow);
    }
  }

  void _applyGlow(PhysicallyBasedMaterial material, double glow) {
    material
      ..emissiveFactor = _windowGlow * glow
      ..emissiveStrength = _windowGlowStrength;
  }
}
