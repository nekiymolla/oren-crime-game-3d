import 'package:crime_oren/player/player_health.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('урон снижает здоровье, смерть — ровно один раз', () {
    final health = PlayerHealth();
    expect(health.takeDamage(40), isFalse);
    expect(health.health, 60);
    expect(health.damageFlash, greaterThan(0));
    expect(health.takeDamage(70), isTrue);
    expect(health.isDead, isTrue);
    expect(health.health, 0);
    expect(health.takeDamage(10), isFalse);
  });

  test('регенерация только после передышки, не выше максимума, мёртвому — нет', () {
    final health = PlayerHealth()..takeDamage(50);
    health.update(PlayerHealth.regenDelaySeconds - 1);
    expect(health.health, 50);
    health.update(2);
    expect(health.health, greaterThan(50));
    health.update(100);
    expect(health.health, PlayerHealth.maxHealth);

    final dead = PlayerHealth()..takeDamage(200);
    dead.update(100);
    expect(dead.health, 0);
    dead.reset();
    expect(dead.isDead, isFalse);
    expect(dead.health, PlayerHealth.maxHealth);
  });

  test('вспышка урона гаснет', () {
    final health = PlayerHealth()..takeDamage(10);
    health.update(1.0);
    expect(health.damageFlash, 0);
  });
}
