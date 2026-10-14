import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import '../time/day_night.dart';
import 'weather.dart';

/// Базовая цветокоррекция и bloom — те же числа, что в
/// Game._applyEnvironmentSettings; погода и время суток дают к ним поправки.
abstract final class BaseLook {
  static const double saturation = 1.1;
  static const double contrast = 1.05;
  static const double temperature = 0.05;
  static const double bloomIntensity = 0.18;
}

/// Погода и "вайс-сити" на экране: туман со свечением к солнцу, лучи
/// солнца сквозь деревья и дома, блики линз, неоновый грейдинг на закате и
/// ночью, дождь/снег вокруг камеры, молнии, снег на земле и кронах.
///
/// Эффекты пишутся в живые объекты сцены (scene.fog, scene.godRays,
/// scene.postProcess.*), а не новым EnvironmentSettings каждый кадр:
/// тот — полный снимок вида и перенастраивает всё сразу.
class WeatherView {
  WeatherView({
    required this.scene,
    required this.godRaysAllowed,
    required this.bloomAllowed,
    required int maxParticles,
    math.Random? random,
  }) : _random = random ?? math.Random(),
       _rain = _Precipitation(
         InstancedMesh(
           geometry: CuboidGeometry(vm.Vector3(0.012, 0.55, 0.012)),
           material: UnlitMaterial()..baseColorFactor = vm.Vector4(0.62, 0.68, 0.78, 1.0),
         ),
         maxParticles,
         fallSpeed: 14.0,
         random: random ?? math.Random(),
       ),
       _snow = _Precipitation(
         InstancedMesh(
           geometry: IcosphereGeometry(radius: 0.035, subdivisions: 0),
           material: UnlitMaterial()..baseColorFactor = vm.Vector4(0.95, 0.96, 1.0, 1.0),
         ),
         maxParticles,
         fallSpeed: 1.4,
         random: random ?? math.Random(),
       );

  final Scene scene;

  /// Пресет качества разрешает лучи (они — самый дорогой проход здесь) и
  /// bloom (без него нет бликов линз).
  final bool Function() godRaysAllowed;
  final bool Function() bloomAllowed;

  final math.Random _random;
  final _Precipitation _rain;
  final _Precipitation _snow;

  double _flash = 0.0;
  double _secondsToStrike = 6.0;
  double _strikeAge = 99.0;

  /// Яркость вспышки молнии сейчас (0..1) — для applyWeather.
  double get lightningFlash => _flash;

  Node buildNode() => Node()
    ..addComponent(InstancedMeshComponent(_rain.mesh))
    ..addComponent(InstancedMeshComponent(_snow.mesh));

  /// Молнии: случайные удары, каждый — двойная вспышка ~0.4 с.
  void updateLightning(double dt, WeatherParams weather) {
    _strikeAge += dt;
    if (weather.lightning > 0.05) {
      _secondsToStrike -= dt * weather.lightning;
      if (_secondsToStrike <= 0) {
        _secondsToStrike = 4.0 + _random.nextDouble() * 10.0;
        _strikeAge = 0.0;
      }
    }
    final a = _strikeAge;
    // Два всплеска: основной и короткий отголосок.
    _flash = math.max(_pulse(a, 0.0, 0.18), 0.6 * _pulse(a, 0.25, 0.12));
  }

  static double _pulse(double age, double start, double length) {
    final t = (age - start) / length;
    if (t < 0 || t > 1) return 0.0;
    return 1.0 - t;
  }

  /// Пост-эффекты, туман и осадки под текущий свет [sky] (уже с погодой).
  void update(double dt, SkyLighting sky, WeatherParams weather, vm.Vector3 camera) {
    final cloud = weather.cloudCover;
    final sunUp = sky.sunElevation > 0.0;
    final golden = sky.goldenHour;

    // Туман: цвета горизонта (днём голубоватая дымка, на закате розовая),
    // в жару — тёплое марево. sunInScatter — свечение дымки в сторону
    // солнца: на закате это половина "вайс-сити".
    final warm = vm.Vector3(1.0, 0.78, 0.5) * (0.2126 * sky.horizonColor.x + 0.7152 * sky.horizonColor.y + 0.0722 * sky.horizonColor.z);
    scene.fog
      ..enabled = true
      ..mode = FogMode.exponential
      ..color.setFrom(sky.horizonColor + (warm - sky.horizonColor) * weather.fogWarmth)
      ..density = weather.fogDensity
      ..maxOpacity = 1.0
      ..sunInScatter = sunUp ? (0.25 + 0.6 * golden) * (1.0 - cloud) : 0.0
      ..sunInScatterExponent = 6.0;

    // Лучи солнца: сильнее у низкого солнца, нет при сплошной облачности
    // и ночью. Нужен солнечный свет с тенями — его даёт DayNightView.
    final rays = weather.sunRays * (1.0 - cloud) * (sunUp ? 1.0 : 0.0);
    scene.godRays
      ..enabled = godRaysAllowed() && rays > 0.05 && sky.castsShadow
      ..intensity = rays * (0.45 + 0.9 * golden)
      ..density = 0.55
      ..anisotropy = 0.75
      ..color.setFrom(sky.lightColor);

    // Блик линз от солнца — только когда солнце реально видно.
    final flare = (1.0 - cloud) * weather.sunRays * (sunUp ? 1.0 : 0.0);
    scene.postProcess.bloom.lensFlare
      ..enabled = bloomAllowed() && flare > 0.2
      ..intensity = 0.35 * flare
      ..haloIntensity = 0.25 * flare
      ..ghostCount = 4;

    // Грейдинг: погода + "неон" — на закате и ночью сдвиг в мадженту и
    // насыщенность (розово-фиолетовые сумерки Вайс-Сити), ночью сильнее
    // bloom, чтобы фары, светофоры и окна светились ореолом.
    final neon = math.max(golden, sky.nightFactor * 0.7);
    scene.postProcess.colorGrading
      ..saturation = BaseLook.saturation + weather.saturation + 0.12 * neon
      ..contrast = BaseLook.contrast + weather.contrast + 0.04 * neon
      ..temperature = BaseLook.temperature + weather.temperature + 0.04 * golden
      ..tint = -0.07 * neon;
    scene.postProcess.bloom.intensity = BaseLook.bloomIntensity + 0.14 * sky.nightFactor + 0.06 * golden;

    // Капли и снежинки unlit — ночью они светились бы белым; тонируем их
    // освещённостью сцены (вспышка молнии входит в unlitTint).
    _rain.tint(sky.unlitTint);
    _snow.tint(sky.unlitTint);
    _rain.update(dt, camera, intensity: weather.rain, wind: weather.wind, tilt: true);
    _snow.update(dt, camera, intensity: weather.snow, wind: weather.wind, tilt: false);
  }
}

/// Капли или снежинки в коробке вокруг камеры: падают, сносятся ветром и
/// по кругу переносятся на другую сторону коробки — частиц ровно столько,
/// сколько видно, независимо от размера карты. Неактивные (при слабых
/// осадках) спрятаны глубоко под землёй.
class _Precipitation {
  _Precipitation(this.mesh, this.maxCount, {required this.fallSpeed, required math.Random random}) {
    for (var i = 0; i < maxCount; i++) {
      _local.add(vm.Vector3(
        (random.nextDouble() - 0.5) * _boxWidth,
        random.nextDouble() * _boxHeight,
        (random.nextDouble() - 0.5) * _boxWidth,
      ));
      _phase.add(random.nextDouble() * math.pi * 2);
      mesh.addInstance(vm.Matrix4.translationValues(0, _hiddenY, 0));
    }
  }

  final InstancedMesh mesh;
  final int maxCount;
  late final vm.Vector4 _dayColor = (mesh.material as UnlitMaterial).baseColorFactor.clone();

  void tint(vm.Vector3 light) {
    (mesh.material as UnlitMaterial).baseColorFactor = vm.Vector4(
      _dayColor.x * light.x,
      _dayColor.y * light.y,
      _dayColor.z * light.z,
      _dayColor.w,
    );
  }

  final double fallSpeed;
  final List<vm.Vector3> _local = [];
  final List<double> _phase = [];
  double _time = 0.0;
  bool _visible = false;
  bool _anchored = false;

  // Коробка поменьше — те же частицы гуще у глаз (на 34 м дождь читался
  // редкими штрихами).
  static const double _boxWidth = 24.0;
  static const double _boxHeight = 14.0;
  static const double _hiddenY = -1000.0;

  void update(double dt, vm.Vector3 camera, {required double intensity, required double wind, required bool tilt}) {
    final active = (maxCount * intensity.clamp(0.0, 1.0)).round();
    if (active == 0) {
      if (_visible) {
        mesh.updateInstanceTransforms((transforms) {
          for (final m in transforms) {
            m.setTranslationRaw(0, _hiddenY, 0);
          }
        }, recomputeWinding: false);
        _visible = false;
      }
      return;
    }
    _visible = true;
    _time += dt;

    // Ветер дует вдоль +X (условно), дождь косит в ту же сторону.
    final windSpeed = wind * (tilt ? 7.0 : 4.0);
    final half = _boxWidth / 2;
    final base = tilt
        ? (vm.Matrix4.identity()..setRotationZ(-math.atan2(windSpeed, fallSpeed)))
        : vm.Matrix4.identity();

    if (!_anchored) {
      // Первый показ — раскладываем коробку вокруг камеры.
      _anchored = true;
      for (final p in _local) {
        p.x += camera.x;
        p.z += camera.z;
      }
    }

    mesh.updateInstanceTransforms((transforms) {
      for (var i = 0; i < maxCount; i++) {
        final m = transforms[i];
        if (i >= active) {
          m.setTranslationRaw(0, _hiddenY, 0);
          continue;
        }
        // x/z частицы — мировые: она неподвижна в мире, а коробка "едет"
        // за камерой, перекидывая частицы с края на край. y — высота над
        // низом коробки (чуть ниже камеры).
        final p = _local[i];
        p.y -= fallSpeed * dt;
        if (p.y < 0) p.y += _boxHeight;
        p.x += windSpeed * dt;
        if (!tilt) {
          // Снежинки кружатся.
          p.x += math.sin(_time * 1.3 + _phase[i]) * 0.4 * dt;
          p.z += math.cos(_time * 1.1 + _phase[i]) * 0.4 * dt;
        }
        p.x = camera.x + _wrap(p.x - camera.x, half);
        p.z = camera.z + _wrap(p.z - camera.z, half);
        m.setFrom(base);
        m.setTranslationRaw(p.x, camera.y - 4.0 + p.y, p.z);
      }
    }, recomputeWinding: false);
  }

  /// Держит смещение в [-half, half).
  static double _wrap(double v, double half) {
    final size = half * 2;
    return ((v + half) % size + size) % size - half;
  }
}
