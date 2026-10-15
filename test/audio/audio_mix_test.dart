import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crime_oren/audio/audio_mix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('обороты и громкость двигателя растут со скоростью', () {
    expect(enginePitch(0, 50), closeTo(0.8, 1e-9));
    expect(enginePitch(50, 50), closeTo(3.0, 1e-9));
    expect(enginePitch(100, 50), closeTo(3.0, 1e-9)); // не выше отсечки
    expect(enginePitch(25, 50), greaterThan(enginePitch(10, 50)));
    expect(engineVolume(50, 50), greaterThan(engineVolume(0, 50)));
  });

  test('шины визжат только в заносе на скорости', () {
    expect(screechVolume(driftFactor: 0.8, speed: 3), 0);
    expect(screechVolume(driftFactor: 0.05, speed: 20), 0);
    expect(screechVolume(driftFactor: 0.6, speed: 20), greaterThan(0.5));
  });

  test('погода: дождь и ветер слышны, в машине глуше, ночью город тише', () {
    final outside = ambienceMix(rain: 1, snow: 0, wind: 0.9, nightFactor: 0, inVehicle: false);
    final inCar = ambienceMix(rain: 1, snow: 0, wind: 0.9, nightFactor: 0, inVehicle: true);
    final clearNight = ambienceMix(rain: 0, snow: 0, wind: 0.1, nightFactor: 1, inVehicle: false);
    expect(outside.rain, greaterThan(0.8));
    expect(inCar.rain, lessThan(outside.rain));
    expect(clearNight.rain, 0);
    expect(clearNight.wind, 0);
    expect(clearNight.city, lessThan(outside.city));
  });

  test('шаги: при ходьбе реже, чем на бегу; стоя — тишина', () {
    int steps(double speed) {
      final timer = FootstepTimer();
      var count = 0;
      for (var i = 0; i < 600; i++) {
        if (timer.update(1 / 60, speed: speed, grounded: true)) count++;
      }
      return count;
    }

    expect(steps(0), 0);
    expect(steps(4.5), inInclusiveRange(18, 26)); // ~2 шага в секунду
    expect(steps(8.1), greaterThan(steps(4.5)));
    final airborne = FootstepTimer();
    expect(airborne.update(1, speed: 5, grounded: false), isFalse);
  });

  test('гром — один раскат на вспышку, с задержкой', () {
    final thunder = ThunderScheduler(Random(1));
    expect(thunder.update(0.016, 1.0), 0); // вспышка — сразу не гремит
    expect(thunder.update(0.016, 1.0), 0); // та же вспышка — не второй раскат
    var total = 0;
    for (var i = 0; i < 300; i++) {
      total += thunder.update(0.016, 0.0);
    }
    expect(total, 1);
  });

  test('все звуки, которые грузит AudioSystem, лежат в assets/sounds и это WAV', () {
    final source = File('lib/audio/audio_system.dart').readAsStringSync();
    final list = RegExp(r"_clipNames = \[([^\]]*)\]").firstMatch(source)!.group(1)!;
    final names = RegExp(r"'([a-z_]+)'").allMatches(list).map((m) => m.group(1)!).toList();
    expect(names, isNotEmpty);
    for (final name in names) {
      final file = File('assets/sounds/$name.wav');
      expect(file.existsSync(), isTrue, reason: name);
      final header = Uint8List.fromList(file.readAsBytesSync().take(12).toList());
      expect(String.fromCharCodes(header.sublist(0, 4)), 'RIFF', reason: name);
      expect(String.fromCharCodes(header.sublist(8, 12)), 'WAVE', reason: name);
    }
  });
}
