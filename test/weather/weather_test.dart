import 'dart:math' as math;

import 'package:crime_oren/weather/weather.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('у каждого состояния есть пресет', () {
    for (final kind in WeatherKind.values) {
      expect(weatherPresets[kind], isNotNull, reason: kind.label);
    }
  });

  test('переход плавный: на полпути — между пресетами, в конце — целевой', () {
    final weather = WeatherSystem(initial: WeatherKind.clear);
    weather.setWeather(WeatherKind.rain);
    weather.update(WeatherSystem.transitionSeconds / 2, gameHoursPassed: 0, dayOfYear: 287);
    final mid = weather.params.rain;
    expect(mid, greaterThan(0.1));
    expect(mid, lessThan(weatherPresets[WeatherKind.rain]!.rain - 0.1));
    weather.update(WeatherSystem.transitionSeconds, gameHoursPassed: 0, dayOfYear: 287);
    expect(weather.params.rain, closeTo(weatherPresets[WeatherKind.rain]!.rain, 1e-9));
  });

  test('снег копится постепенно и тает после', () {
    final weather = WeatherSystem(initial: WeatherKind.snow);
    weather.update(30, gameHoursPassed: 0, dayOfYear: 10);
    final early = weather.params.snowCover;
    expect(early, greaterThan(0.1));
    expect(early, lessThan(0.5));
    for (var i = 0; i < 10; i++) {
      weather.update(30, gameHoursPassed: 0, dayOfYear: 10);
    }
    expect(weather.params.snowCover, closeTo(weatherPresets[WeatherKind.snow]!.snowCover, 0.01));

    weather.setWeather(WeatherKind.clear);
    for (var i = 0; i < 20; i++) {
      weather.update(30, gameHoursPassed: 0, dayOfYear: 10);
    }
    expect(weather.params.snowCover, lessThan(0.05));
  });

  test('в октябре жары не бывает, снег редкость; зимой снега много', () {
    final random = math.Random(1);
    var octoberHeat = 0, octoberSnow = 0, winterSnow = 0;
    for (var i = 0; i < 4000; i++) {
      // Только из не-снежной погоды: из снегопада снег продолжается в любой
      // сезон, вопрос — как часто он НАЧИНАЕТСЯ.
      const start = [WeatherKind.clear, WeatherKind.cloudy, WeatherKind.overcast, WeatherKind.drizzle, WeatherKind.fog];
      final current = start[random.nextInt(start.length)];
      final october = nextWeather(current, 287, random);
      if (october == WeatherKind.heat) octoberHeat++;
      if (october == WeatherKind.lightSnow || october == WeatherKind.snow || october == WeatherKind.blizzard) octoberSnow++;
      final january = nextWeather(current, 15, random);
      if (january == WeatherKind.lightSnow || january == WeatherKind.snow || january == WeatherKind.blizzard) winterSnow++;
    }
    expect(octoberHeat, 0);
    expect(winterSnow, greaterThan(octoberSnow * 4));
  });

  test('из ясной сразу в метель не прыгает', () {
    final random = math.Random(2);
    for (var i = 0; i < 1000; i++) {
      final next = nextWeather(WeatherKind.clear, 15, random);
      expect(next, isNot(WeatherKind.blizzard));
      expect(next, isNot(WeatherKind.storm));
    }
  });

  test('погода меняется сама раз в несколько игровых часов', () {
    final weather = WeatherSystem(initial: WeatherKind.clear, random: math.Random(3));
    final seen = <WeatherKind>{};
    for (var hour = 0; hour < 48; hour++) {
      weather.update(1, gameHoursPassed: 1, dayOfYear: 287);
      seen.add(weather.kind);
    }
    expect(seen.length, greaterThan(2));
  });

  test('осадки — лестницей: туман растёт с силой, слабые — без тумана', () {
    final clearFog = weatherPresets[WeatherKind.clear]!.fogDensity;
    for (final ladder in [
      [WeatherKind.drizzle, WeatherKind.rain, WeatherKind.heavyRain, WeatherKind.storm],
      [WeatherKind.lightSnow, WeatherKind.snow, WeatherKind.blizzard],
    ]) {
      expect(weatherPresets[ladder.first]!.fogDensity, lessThan(clearFog), reason: ladder.first.label);
      for (var i = 1; i < ladder.length; i++) {
        final weaker = weatherPresets[ladder[i - 1]]!;
        final stronger = weatherPresets[ladder[i]]!;
        expect(stronger.fogDensity, greaterThan(weaker.fogDensity), reason: ladder[i].label);
        expect(stronger.rain + stronger.snow, greaterThan(weaker.rain + weaker.snow), reason: ladder[i].label);
      }
    }
  });

  test('дождь меняется на одну ступень, без прыжков', () {
    final random = math.Random(4);
    for (var i = 0; i < 2000; i++) {
      expect(nextWeather(WeatherKind.drizzle, 287, random), isNot(anyOf(WeatherKind.heavyRain, WeatherKind.storm)));
      expect(nextWeather(WeatherKind.storm, 287, random), isNot(anyOf(WeatherKind.drizzle, WeatherKind.clear)));
      expect(nextWeather(WeatherKind.clear, 287, random), isNot(anyOf(WeatherKind.rain, WeatherKind.heavyRain)));
    }
  });
}
