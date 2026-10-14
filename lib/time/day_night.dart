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

  void advance(double realSeconds) {
    hours += realSeconds * gameMinutesPerSecond / 60.0;
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
}

/// Дневные числа — те же, что были у статичного неба до суточного цикла
/// (см. Game._buildSky), чтобы днём картинка не изменилась.
final vm.Vector3 _dayZenith = vm.Vector3(0.20, 0.40, 0.68);
final vm.Vector3 _dayHorizon = vm.Vector3(0.72, 0.80, 0.85);
final vm.Vector3 _dayGround = vm.Vector3(0.30, 0.30, 0.27);
final vm.Vector3 _sunsetZenith = vm.Vector3(0.22, 0.27, 0.50);
final vm.Vector3 _sunsetHorizon = vm.Vector3(0.95, 0.55, 0.32);
final vm.Vector3 _nightZenith = vm.Vector3(0.008, 0.012, 0.035);
final vm.Vector3 _nightHorizon = vm.Vector3(0.035, 0.045, 0.085);
final vm.Vector3 _nightGround = vm.Vector3(0.02, 0.02, 0.025);

/// Луна — без своей орбиты: висит высоко на юго-востоке и даёт ночью
/// слабый холодный свет, чтобы город не проваливался в чёрное.
final vm.Vector3 _moonDirection = vm.Vector3(0.35, 0.8, 0.45)..normalize();
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

  // Над горизонтом светит солнце; ниже — луна (в сумерках обе почти
  // гаснут, так что смена направления незаметна).
  final isSunUp = elevation > -0.02;
  final lightDirection = isSunUp ? sun : _moonDirection.clone();
  final lightColor = isSunUp ? sunColor : _moonColor.clone();
  final lightIntensity = isSunUp ? _daySunIntensity * dayT : _moonIntensity * nightFactor;

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

  return SkyLighting(
    lightDirection: lightDirection,
    lightColor: lightColor,
    lightIntensity: lightIntensity,
    castsShadow: lightIntensity > 0.05,
    environmentIntensity: environmentIntensity,
    zenithColor: zenith,
    horizonColor: horizon,
    groundColor: ground,
    // HDR-диск солнца в небе; ночью гаснет вместе с ним.
    sunDiskColor: sunColor * (3.0 * dayT),
    nightFactor: nightFactor,
    sunElevation: elevation,
    unlitTint: unlitTint,
  );
}

double _smoothstep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

vm.Vector3 _mix(vm.Vector3 a, vm.Vector3 b, double t) => a + (b - a) * t;
