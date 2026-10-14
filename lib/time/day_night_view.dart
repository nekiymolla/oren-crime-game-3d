import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../weather/weather.dart';
import '../weather/weather_lighting.dart';
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

  /// Видимое небо — шейдер crime_sky.fmat (солнце, луна, звёзды). null —
  /// не загрузилось, тогда фоном остаётся [sky].
  PreprocessedSky? visibleSky;
  double _skyTime = 0.0;

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

  /// Снег на земле — не чисто белый, иначе днём выжигается в тонмаппинге.
  static final vm.Vector3 _snowColor = vm.Vector3(0.82, 0.85, 0.9);

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

  /// [weather] — погода поверх суточного цикла (облака гасят солнце,
  /// молния вспыхивает), [lightningFlash] — яркость вспышки сейчас.
  void update(double deltaSeconds, {WeatherParams? weather, double lightningFlash = 0.0}) {
    clock.advance(deltaSeconds);
    final clear = evaluateSky(clock.hours, clock.dayOfYear);
    final lighting = _last = weather == null
        ? clear
        : applyWeather(clear, weather, lightningFlash: lightningFlash);
    final snowCover = weather?.snowCover ?? 0.0;

    sky
      ..zenithColor = lighting.zenithColor
      ..horizonColor = lighting.horizonColor
      ..groundColor = lighting.groundColor
      ..sunDirection = sunDirection(clock.hours, clock.dayOfYear)
      ..sunColor = lighting.sunDiskColor;
    scene.environmentIntensity = lighting.environmentIntensity;

    final shaderSky = visibleSky;
    if (shaderSky != null) {
      _skyTime += deltaSeconds;
      shaderSky.parameters
        ..setVec3('zenith_color', lighting.zenithColor)
        ..setVec3('horizon_color', lighting.horizonColor)
        ..setVec3('ground_color', lighting.groundColor)
        ..setVec3('sun_direction', lighting.sunDirectionToSun)
        ..setVec3('sun_color', lighting.sunDiskColor)
        ..setVec3('sun_glow', lighting.sunGlowColor)
        ..setVec3('moon_direction', lighting.moonDirectionToMoon)
        ..setFloat('moon_brightness', lighting.moonIllumination > 0.0 ? 1.0 - 0.95 * (weather?.cloudCover ?? 0.0) : 0.0)
        ..setFloat('star_intensity', lighting.starIntensity)
        ..setFloat('time_seconds', _skyTime);
    }
    final tint = lighting.unlitTint;
    for (var i = 0; i < unlitSurfaces.length; i++) {
      // Снег ложится на подложку-газон: цвет уходит к белому.
      final day = _unlitDayColors[i];
      final r = day.x + (_snowColor.x - day.x) * snowCover;
      final g = day.y + (_snowColor.y - day.y) * snowCover;
      final b = day.z + (_snowColor.z - day.z) * snowCover;
      unlitSurfaces[i].baseColorFactor = vm.Vector4(r * tint.x, g * tint.y, b * tint.z, day.w);
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
