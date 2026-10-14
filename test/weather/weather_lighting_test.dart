import 'package:crime_oren/time/day_night.dart';
import 'package:crime_oren/weather/weather.dart';
import 'package:crime_oren/weather/weather_lighting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final day = evaluateSky(13.0, 287);

  test('ясно — свет не трогается', () {
    final clear = applyWeather(day, weatherPresets[WeatherKind.clear]!);
    expect(clear.lightIntensity, day.lightIntensity);
    expect(clear.castsShadow, isTrue);
    expect(clear.zenithColor.b, closeTo(day.zenithColor.b, 1e-9));
  });

  test('пасмурно — солнце гаснет, теней нет, небо серое', () {
    final overcast = applyWeather(day, weatherPresets[WeatherKind.overcast]!);
    expect(overcast.lightIntensity, lessThan(day.lightIntensity * 0.35));
    expect(overcast.castsShadow, isFalse);
    expect(overcast.sunDiskColor.x, lessThan(day.sunDiskColor.x * 0.01)); // от диска <1%
    // Синева зенита уходит: разница синего и красного каналов меньше.
    final dayBlue = day.zenithColor.b - day.zenithColor.r;
    final overcastBlue = overcast.zenithColor.b - overcast.zenithColor.r;
    expect(overcastBlue, lessThan(dayBlue * 0.3));
  });

  test('пасмурной ночью небо не светлеет', () {
    final night = evaluateSky(1.0, 287);
    final overcastNight = applyWeather(night, weatherPresets[WeatherKind.overcast]!);
    expect(overcastNight.horizonColor.length, lessThanOrEqualTo(night.horizonColor.length * 1.05));
  });

  test('молния вспыхивает светом неба', () {
    final night = evaluateSky(1.0, 287);
    final storm = weatherPresets[WeatherKind.storm]!;
    final dark = applyWeather(night, storm);
    final flash = applyWeather(night, storm, lightningFlash: 1.0);
    expect(flash.environmentIntensity, greaterThan(dark.environmentIntensity + 2.0));
    expect(flash.horizonColor.x, greaterThan(dark.horizonColor.x + 0.5));
  });

  test('золотой час — на закате, а не днём и не глубокой ночью', () {
    expect(evaluateSky(18.4, 287).goldenHour, greaterThan(0.7));
    expect(evaluateSky(13.0, 287).goldenHour, lessThan(0.2));
    expect(evaluateSky(2.0, 287).goldenHour, lessThan(0.5));
  });
}
