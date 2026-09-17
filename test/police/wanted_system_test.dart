import 'package:crime_oren/police/wanted_state.dart';
import 'package:crime_oren/police/wanted_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => wantedState.stars = 0);

  test('наезд на пешехода поднимает звёзды на число сбитых', () {
    final system = WantedSystem();
    system.update(1.0, pedestrianHits: 2);
    expect(wantedState.stars, 2);
  });

  test('превышение скорости поднимает только до 1 звезды, не выше', () {
    final system = WantedSystem();
    system.update(1.0, isSpeeding: true);
    expect(wantedState.stars, 1);
    system.update(1.0, isSpeeding: true);
    expect(wantedState.stars, 1); // не растёт дальше само по себе
  });

  test('звёзды не растут выше maxStars', () {
    final system = WantedSystem();
    system.update(1.0, pedestrianHits: 10);
    expect(wantedState.stars, WantedState.maxStars);
  });

  test('без нарушений звезда снимается через decayIntervalSeconds', () {
    final system = WantedSystem(decayIntervalSeconds: 5.0);
    system.update(1.0, pedestrianHits: 1);
    expect(wantedState.stars, 1);

    system.update(4.0); // ещё не прошло decayIntervalSeconds
    expect(wantedState.stars, 1);

    system.update(1.0); // итого 5 секунд без нарушений
    expect(wantedState.stars, 0);
  });

  test('новое нарушение сбрасывает отсчёт затухания', () {
    final system = WantedSystem(decayIntervalSeconds: 5.0);
    system.update(1.0, pedestrianHits: 1);
    system.update(4.0);
    system.update(1.0, pedestrianHits: 1); // новое нарушение на 5-й секунде
    expect(wantedState.stars, 2);

    system.update(4.0); // отсчёт должен был сброситься новым нарушением
    expect(wantedState.stars, 2);
  });
}
