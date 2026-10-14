import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

/// Игровые часы: время суток и день года. Чистая логика без flutter_scene
/// (проверяется юнит-тестами), сцену по ним настраивает DayNightView.
class GameClock {
  GameClock({this.hours = 16.5, this.dayOfYear = 287, this.gameMinutesPerSecond = 1.0});

  /// Местное время (Оренбург, UTC+5), часы 0..24.
  double hours;

  /// День года 1..365 — от него склонение солнца (в октябре оно низкое).
  int dayOfYear;

  /// Сколько игровых минут проходит за реальную секунду: 1.0 — сутки за
  /// 24 минуты игры.
  double gameMinutesPerSecond;

  void advance(double realSeconds) => skipHours(realSeconds * gameMinutesPerSecond / 60.0);

  /// Перемотать на [gameHours] игровых часов — в игровых единицах, без
  /// пересчёта через реальное время (кнопка "time +1h" так и ошиблась:
  /// 3600 "реальных секунд" при минуте за секунду — это 60 часов, на
  /// циферблате +12).
  void skipHours(double gameHours) {
    hours += gameHours;
    while (hours >= 24.0) {
      hours -= 24.0;
      dayOfYear = dayOfYear % 365 + 1;
    }
  }

  /// "16:05" — для HUD.
  String get label {
    // +1e-6: 0.1 ч * 60 в double — это 5.999..., а не 6.
    final totalMinutes = (hours * 60 + 1e-6).floor();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}

/// Где Южный район Оренбурга на глобусе — от этого высота и путь солнца.
abstract final class OrenburgSky {
  static const double latitudeDegrees = 51.7155;
  static const double longitudeDegrees = 55.1072;

  /// Часовой пояс UTC+5 — его центральный меридиан 75° в.д., а город
  /// западнее, на 55°: солнечный полдень наступает позже 12:00 на
  /// (75 - 55.1) / 15 ~ 1.3 часа, около 13:17 по часам. Без этого закат
  /// в октябре был бы в 17:15 вместо реальных ~18:30.
  static const double timezoneMeridianDegrees = 75.0;
}

/// Направление НА солнце в координатах игры (x — восток, y — вверх,
/// z — юг; см. calibration.json пайплайна) для времени [hours] и дня года
/// [dayOfYear].
vm.Vector3 sunDirection(double hours, int dayOfYear) {
  const deg = math.pi / 180.0;
  final latitude = OrenburgSky.latitudeDegrees * deg;
  // Склонение — простая косинусная аппроксимация, точности до градуса
  // для игры с запасом.
  final declination = -23.44 * deg * math.cos(2 * math.pi / 365.0 * (dayOfYear + 10));
  final solarNoon = 12.0 + (OrenburgSky.timezoneMeridianDegrees - OrenburgSky.longitudeDegrees) / 15.0;
  final hourAngle = (hours - solarNoon) * 15.0 * deg;

  final east = -math.cos(declination) * math.sin(hourAngle);
  final north = math.sin(declination) * math.cos(latitude) -
      math.cos(declination) * math.sin(latitude) * math.cos(hourAngle);
  final up = math.sin(declination) * math.sin(latitude) +
      math.cos(declination) * math.cos(latitude) * math.cos(hourAngle);
  return vm.Vector3(east, up, -north)..normalize();
}

/// Синодический месяц — от новолуния до новолуния, дни.
const double synodicMonthDays = 29.53;

/// День года, на который приходится "новолуние" игрового календаря. Не
/// астрономическая дата: выбран так, чтобы к старту игры (14 октября) луна
/// была растущей, ~10 дней, и вечером стояла высоко — её видно сразу.
const double _newMoonDayOfYear = 277.0;

/// Возраст луны в днях от новолуния (0..29.53).
double moonAgeDays(double hours, int dayOfYear) {
  final days = dayOfYear + hours / 24.0 - _newMoonDayOfYear;
  return (days % synodicMonthDays + synodicMonthDays) % synodicMonthDays;
}

/// Освещённая доля диска луны: 0 — новолуние, 1 — полнолуние.
double moonIllumination(double hours, int dayOfYear) {
  final phase = 2 * math.pi * moonAgeDays(hours, dayOfYear) / synodicMonthDays;
  return (1 - math.cos(phase)) / 2;
}

/// Направление НА луну. Упрощение: луна идёт по пути солнца, но отстаёт
/// на долю суток, равную её возрасту в месяцах (в полнолуние — на 12
/// часов: напротив солнца). Отсюда и восход на ~50 минут позже каждый день.
/// Наклон орбиты луны не учитываем — для игры незаметно.
vm.Vector3 moonDirection(double hours, int dayOfYear) {
  final lagHours = moonAgeDays(hours, dayOfYear) / synodicMonthDays * 24.0;
  return sunDirection(hours - lagHours, dayOfYear);
}

/// Свет и небо на данный момент — всё, что нужно сцене.
class SkyLighting {
  SkyLighting({
    required this.lightDirection,
    required this.lightColor,
    required this.lightIntensity,
    required this.castsShadow,
    required this.environmentIntensity,
    required this.zenithColor,
    required this.horizonColor,
    required this.groundColor,
    required this.sunDiskColor,
    required this.nightFactor,
    required this.sunElevation,
    required this.unlitTint,
    required this.sunDirectionToSun,
    required this.moonDirectionToMoon,
    required this.moonIllumination,
    required this.starIntensity,
    required this.sunGlowColor,
  });

  /// Направление НА источник (солнце днём, луна ночью).
  final vm.Vector3 lightDirection;
  final vm.Vector3 lightColor;
  final double lightIntensity;
  final bool castsShadow;

  /// Множитель освещения от неба (Scene.environmentIntensity).
  final double environmentIntensity;

  final vm.Vector3 zenithColor;
  final vm.Vector3 horizonColor;
  final vm.Vector3 groundColor;
  final vm.Vector3 sunDiskColor;

  /// 0 — день, 1 — ночь: по нему горят окна, фары, фонари.
  final double nightFactor;

  /// Синус высоты солнца над горизонтом (отрицательный — под горизонтом).
  final double sunElevation;

  /// Множитель цвета для unlit-поверхностей (плейсхолдер-земля): на них
  /// свет не действует, и без этого ночью земля оставалась ярко-зелёной
  /// под чёрным небом. Днём (1, 1, 1) — дневной вид не меняется.
  final vm.Vector3 unlitTint;

  /// Для шейдера неба (crime_sky.fmat): где солнце и луна, фаза луны,
  /// яркость звёзд и узкой короны солнца.
  final vm.Vector3 sunDirectionToSun;
  final vm.Vector3 moonDirectionToMoon;
  final double moonIllumination;
  final double starIntensity;
  final vm.Vector3 sunGlowColor;

  /// Насколько сейчас "золотой час" (закат/рассвет/сумерки): 1 — солнце у
  /// горизонта, 0 — высоко или глубокая ночь. По нему — неоновый
  /// грейдинг в духе Вайс-Сити и свечение дымки к солнцу.
  double get goldenHour => (1.0 - _smoothstep(0.0, 0.28, sunElevation.abs())) * (1.0 - nightFactor * 0.6);

  SkyLighting copyWith({
    double? lightIntensity,
    bool? castsShadow,
    double? environmentIntensity,
    vm.Vector3? zenithColor,
    vm.Vector3? horizonColor,
    vm.Vector3? sunDiskColor,
    vm.Vector3? unlitTint,
    double? starIntensity,
    vm.Vector3? sunGlowColor,
    double? moonVisibility,
  }) => SkyLighting(
    lightDirection: lightDirection,
    lightColor: lightColor,
    lightIntensity: lightIntensity ?? this.lightIntensity,
    castsShadow: castsShadow ?? this.castsShadow,
    environmentIntensity: environmentIntensity ?? this.environmentIntensity,
    zenithColor: zenithColor ?? this.zenithColor,
    horizonColor: horizonColor ?? this.horizonColor,
    groundColor: groundColor,
    sunDiskColor: sunDiskColor ?? this.sunDiskColor,
    nightFactor: nightFactor,
    sunElevation: sunElevation,
    unlitTint: unlitTint ?? this.unlitTint,
    sunDirectionToSun: sunDirectionToSun,
    moonDirectionToMoon: moonDirectionToMoon,
    moonIllumination: moonIllumination * (moonVisibility ?? 1.0),
    starIntensity: starIntensity ?? this.starIntensity,
    sunGlowColor: sunGlowColor ?? this.sunGlowColor,
  );
}

/// Дневные числа — те же, что были у статичного неба до суточного цикла
/// (см. Game._buildSky), чтобы днём картинка не изменилась.
final vm.Vector3 _dayZenith = vm.Vector3(0.20, 0.40, 0.68);
final vm.Vector3 _dayHorizon = vm.Vector3(0.72, 0.80, 0.85);
final vm.Vector3 _dayGround = vm.Vector3(0.30, 0.30, 0.27);
// Закат и ночь — в духе Вайс-Сити: розово-оранжевый горизонт под
// фиолетовым зенитом, ночью — глубокий сине-фиолетовый, а не серо-чёрный.
final vm.Vector3 _sunsetZenith = vm.Vector3(0.34, 0.20, 0.52);
final vm.Vector3 _sunsetHorizon = vm.Vector3(1.0, 0.46, 0.36);
final vm.Vector3 _nightZenith = vm.Vector3(0.016, 0.01, 0.045);
final vm.Vector3 _nightHorizon = vm.Vector3(0.06, 0.035, 0.1);
final vm.Vector3 _nightGround = vm.Vector3(0.02, 0.02, 0.025);

/// Ночью без луны (не взошла / новолуние) свет идёт "от неба" — почти
/// сверху и очень слабый, без теней: город не проваливается в чёрное.
final vm.Vector3 _skyglowDirection = vm.Vector3(0.15, 1.0, 0.1)..normalize();
final vm.Vector3 _moonColor = vm.Vector3(0.55, 0.65, 1.0);

/// Дневная сила солнца — как было до суточного цикла.
const double _daySunIntensity = 4.0;
// Ночь в игре светлее настоящей — в полной темноте играть нельзя.
const double _moonIntensity = 0.5;
const double _nightEnvironment = 0.15;

SkyLighting evaluateSky(double hours, int dayOfYear) {
  final sun = sunDirection(hours, dayOfYear);
  final elevation = sun.y;

  // День -> закат: тёплеет и слабеет у горизонта (как в реальности: свет
  // проходит больше атмосферы).
  final dayT = _smoothstep(-0.02, 0.25, elevation); // 0 у горизонта, 1 днём
  final sunsetT = 1.0 - _smoothstep(0.0, 0.3, elevation.abs()); // пик на горизонте
  final nightFactor = 1.0 - _smoothstep(-0.12, 0.04, elevation); // 1 глубокой ночью

  final sunColor = _mix(vm.Vector3(1.0, 0.55, 0.25), vm.Vector3(1.0, 0.96, 0.88), dayT);

  // Над горизонтом светит солнце; ниже — луна, если она взошла, со
  // светом по фазе (в полнолуние ярко, в серп — едва), иначе слабое
  // свечение неба. В сумерках всё почти гаснет — смена незаметна.
  final moon = moonDirection(hours, dayOfYear);
  final illumination = moonIllumination(hours, dayOfYear);
  final moonUp = _smoothstep(0.0, 0.12, moon.y);
  final isSunUp = elevation > -0.02;
  final useMoon = !isSunUp && moonUp > 0.0;
  final lightDirection = isSunUp ? sun : (useMoon ? moon.clone() : _skyglowDirection.clone());
  final lightColor = isSunUp ? sunColor : _moonColor.clone();
  final lightIntensity = isSunUp
      ? _daySunIntensity * dayT
      : _moonIntensity * nightFactor * (useMoon ? (0.3 + 0.7 * illumination) * moonUp : 0.25);

  final environmentIntensity = _nightEnvironment + (1.0 - _nightEnvironment) * (1.0 - nightFactor);

  var zenith = _mix(_dayZenith, _sunsetZenith, sunsetT * (1 - nightFactor));
  var horizon = _mix(_dayHorizon, _sunsetHorizon, sunsetT * (1 - nightFactor));
  zenith = _mix(zenith, _nightZenith, nightFactor);
  horizon = _mix(horizon, _nightHorizon, nightFactor);
  final ground = _mix(_dayGround, _nightGround, nightFactor);

  // Насколько освещена была бы обычная поверхность: половина от неба,
  // половина от солнца/луны (днём ровно 1). Ночью — холодный оттенок.
  final brightness = (0.5 * environmentIntensity + 0.5 * lightIntensity / _daySunIntensity).clamp(0.0, 1.0);
  final unlitTint = _mix(vm.Vector3(1, 1, 1), vm.Vector3(0.7, 0.8, 1.0), nightFactor) * brightness;

  // Солнце для шейдера неба: чёткий HDR-диск (краснее и тусклее у
  // горизонта) и узкая корона; ниже горизонта — гаснет.
  final sunVisible = _smoothstep(-0.03, 0.01, elevation);
  final sunDisk = sunColor * (_sunDiskRadiance * (0.25 + 0.75 * dayT) * sunVisible);
  final sunGlow = sunColor * (_sunGlowStrength * sunVisible);

  return SkyLighting(
    lightDirection: lightDirection,
    lightColor: lightColor,
    lightIntensity: lightIntensity,
    castsShadow: lightIntensity > 0.05,
    environmentIntensity: environmentIntensity,
    zenithColor: zenith,
    horizonColor: horizon,
    groundColor: ground,
    sunDiskColor: sunDisk,
    nightFactor: nightFactor,
    sunElevation: elevation,
    unlitTint: unlitTint,
    sunDirectionToSun: sun,
    moonDirectionToMoon: moon,
    moonIllumination: illumination,
    // Звёзды проступают в глубоких сумерках.
    starIntensity: nightFactor * nightFactor,
    sunGlowColor: sunGlow,
  );
}

/// Яркость диска солнца в шейдере неба (линейный HDR): с запасом выше
/// порога bloom — диск выгорает в белое и светится, как настоящий.
const double _sunDiskRadiance = 40.0;
const double _sunGlowStrength = 1.2;

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

vm.Vector3 _mix(vm.Vector3 a, vm.Vector3 b, double t) => a + (b - a) * t;
