import 'dart:math' as math;

import 'package:crime_oren/time/day_night.dart';
import 'package:flutter_test/flutter_test.dart';

/// Время (часы), когда солнце пересекает горизонт, — перебором с шагом в
/// минуту от [from] до [to].
double _crossing(int day, double from, double to, {required bool rising}) {
  for (var h = from; h < to; h += 1 / 60) {
    final now = sunDirection(h, day).y;
    final next = sunDirection(h + 1 / 60, day).y;
    if (rising ? (now <= 0 && next > 0) : (now > 0 && next <= 0)) return h;
  }
  return double.nan;
}

void main() {
  const october14 = 287;

  test('утром солнце на востоке, в полдень на юге, вечером на западе', () {
    final morning = sunDirection(9.0, october14);
    expect(morning.x, greaterThan(0.3)); // восток = +X
    final noon = sunDirection(13.3, october14);
    expect(noon.z, greaterThan(0.5)); // юг = +Z
    expect(noon.x.abs(), lessThan(0.1));
    final evening = sunDirection(17.5, october14);
    expect(evening.x, lessThan(-0.3)); // запад = -X
  });

  test('в середине октября в Оренбурге светло примерно с 8 до 18:30', () {
    final sunrise = _crossing(october14, 4, 12, rising: true);
    final sunset = _crossing(october14, 13, 22, rising: false);
    // Реальные ~7:55 и ~18:35 (UTC+5); простая модель — с запасом в 25 минут.
    expect(sunrise, closeTo(7.95, 0.4));
    expect(sunset, closeTo(18.6, 0.4));
  });

  test('в полдень октября солнце низкое, летом — высокое', () {
    const deg = 180 / math.pi;
    final octoberNoon = math.asin(sunDirection(13.3, october14).y) * deg;
    final juneNoon = math.asin(sunDirection(13.3, 172).y) * deg;
    // 90 - 51.7 + склонение: октябрь ~ 29°, июнь ~ 62°.
    expect(octoberNoon, closeTo(29, 2));
    expect(juneNoon, closeTo(61.7, 2));
  });

  test('днём — солнце и полное небо, ночью — луна и ночь', () {
    final day = evaluateSky(13.0, october14);
    expect(day.nightFactor, 0.0);
    expect(day.lightIntensity, greaterThan(3.0));
    expect(day.environmentIntensity, closeTo(1.0, 1e-9));
    expect(day.castsShadow, isTrue);

    final night = evaluateSky(1.0, october14);
    expect(night.nightFactor, closeTo(1.0, 1e-9));
    expect(night.lightIntensity, lessThanOrEqualTo(0.5)); // луна, не солнце
    expect(night.lightDirection.y, greaterThan(0.0)); // свет сверху, не из-под земли
    expect(night.environmentIntensity, lessThan(0.2));

    // Unlit-земля днём не меняется, ночью темнеет и холодеет.
    expect(day.unlitTint.x, closeTo(1.0, 1e-9));
    expect(night.unlitTint.x, lessThan(0.2));
    expect(night.unlitTint.z, greaterThan(night.unlitTint.x));
  });

  test('на закате свет тёплый и слабый', () {
    final sunset = evaluateSky(18.2, october14);
    expect(sunset.lightColor.z, lessThan(sunset.lightColor.x * 0.6)); // рыжий
    expect(sunset.lightIntensity, lessThan(2.0));
    expect(sunset.horizonColor.x, greaterThan(sunset.horizonColor.z));
  });

  test('перемотка на час — ровно час, в том числе через полночь', () {
    final clock = GameClock(hours: 16.5, dayOfYear: 287);
    clock.skipHours(1);
    expect(clock.label, '17:30');
    clock.skipHours(7);
    expect(clock.label, '00:30');
    expect(clock.dayOfYear, 288);
  });

  test('часы идут, переходят через полночь и пишут время', () {
    final clock = GameClock(hours: 23.9, dayOfYear: 365, gameMinutesPerSecond: 1.0);
    clock.advance(12); // +12 игровых минут
    expect(clock.hours, closeTo(0.1, 1e-9));
    expect(clock.dayOfYear, 1);
    expect(clock.label, '00:06');
  });

  test('луна: фазы по месяцу, полнолуние — напротив солнца', () {
    // Новолуние игрового календаря — день 277, полнолуние — через полмесяца.
    expect(moonIllumination(0, 277), closeTo(0.0, 0.01));
    final fullDay = 277 + (synodicMonthDays / 2).floor();
    expect(moonIllumination(12, fullDay), greaterThan(0.95));
    final sun = sunDirection(13.3, fullDay);
    final moon = moonDirection(13.3, fullDay);
    expect(sun.dot(moon), lessThan(-0.8)); // почти напротив
  });

  test('на старте игры луна растущая и вечером высоко', () {
    final illumination = moonIllumination(21, october14);
    expect(illumination, greaterThan(0.5));
    expect(illumination, lessThan(0.95));
    expect(moonDirection(21, october14).y, greaterThan(0.3));
  });

  test('луна восходит каждый день позже примерно на 50 минут', () {
    double rise(int day) {
      for (var h = 0.0; h < 24; h += 1 / 60) {
        if (moonDirection(h, day).y <= 0 && moonDirection(h + 1 / 60, day).y > 0) return h;
      }
      return double.nan;
    }
    final delay = (rise(290) - rise(289)) * 60;
    expect(delay, closeTo(49, 8));
  });

  test('звёзды — только ночью', () {
    expect(evaluateSky(13.0, october14).starIntensity, 0.0);
    expect(evaluateSky(1.0, october14).starIntensity, greaterThan(0.9));
  });
}
