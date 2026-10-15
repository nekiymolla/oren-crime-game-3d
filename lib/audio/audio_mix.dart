import 'dart:math' as math;

/// Числа звукового микса — чистые функции без звукового движка,
/// проверены тестами. Применяет их AudioSystem.

/// Обороты двигателя как скорость воспроизведения петли engine_loop.wav
/// (холостые ~40 Гц): от холостых до "под отсечку" на максималке.
double enginePitch(double speed, double maxSpeed) {
  final ratio = maxSpeed > 0 ? (speed / maxSpeed).clamp(0.0, 1.0) : 0.0;
  return 0.8 + 2.2 * math.sqrt(ratio);
}

/// Двигатель громче под нагрузкой (на скорости).
double engineVolume(double speed, double maxSpeed) {
  final ratio = maxSpeed > 0 ? (speed / maxSpeed).clamp(0.0, 1.0) : 0.0;
  return 0.35 + 0.45 * ratio;
}

/// Визг шин: только в заносе и на скорости.
double screechVolume({required double driftFactor, required double speed}) {
  if (speed < 6.0) return 0.0;
  final drift = ((driftFactor - 0.15) / 0.35).clamp(0.0, 1.0);
  return drift * math.min(1.0, speed / 15.0) * 0.8;
}

/// Громкость фоновых петель: дождь, ветер, город.
({double rain, double wind, double city}) ambienceMix({
  required double rain,
  required double snow,
  required double wind,
  required double nightFactor,
  required bool inVehicle,
}) {
  // В салоне погоду слышно глуше.
  final muffle = inVehicle ? 0.5 : 1.0;
  return (
    rain: (rain * 0.9).clamp(0.0, 1.0) * muffle,
    // Ветер слышен и сам по себе, и в метель.
    wind: (math.max(wind - 0.15, 0.0) * 0.7 + snow * 0.4).clamp(0.0, 1.0) * muffle,
    // Ночью город тише.
    city: (0.35 - 0.15 * nightFactor) * (inVehicle ? 0.6 : 1.0),
  );
}

/// Шаги: интервал зависит от скорости (бег — чаще). [update] возвращает
/// true в кадр, когда пора проиграть шаг.
class FootstepTimer {
  double _untilNext = 0.0;

  bool update(double dt, {required double speed, required bool grounded}) {
    if (!grounded || speed < 0.8) {
      _untilNext = 0.0; // первый шаг — сразу, как пошёл
      return false;
    }
    _untilNext -= dt;
    if (_untilNext > 0.0) return false;
    _untilNext = 2.6 / (speed + 1.2);
    return true;
  }
}

/// Гром: после вспышки молнии с задержкой, как от далёкого разряда.
class ThunderScheduler {
  ThunderScheduler(this._random);

  final math.Random _random;
  final List<double> _pending = [];
  double _lastFlash = 0.0;

  /// [flash] — яркость молнии в этом кадре (WeatherView.lightningFlash).
  /// Возвращает, сколько раскатов грома начинается в этом кадре.
  int update(double dt, double flash) {
    if (flash > 0.5 && _lastFlash <= 0.5) _pending.add(0.4 + _random.nextDouble() * 2.0);
    _lastFlash = flash;
    var due = 0;
    for (var i = _pending.length - 1; i >= 0; i--) {
      _pending[i] -= dt;
      if (_pending[i] <= 0.0) {
        _pending.removeAt(i);
        due++;
      }
    }
    return due;
  }
}
