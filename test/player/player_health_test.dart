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

  test('бронежилет принимает урон первым, не регенерирует, теряется при возрождении', () {
    final health = PlayerHealth()..addArmor(30);
    health.takeDamage(20);
    expect(health.armor, 10);
    expect(health.health, 100);
    health.takeDamage(25); // 10 в броню, 15 в здоровье
    expect(health.armor, 0);
    expect(health.health, 85);
    health.update(100);
    expect(health.armor, 0);
    health.addArmor(500);
    expect(health.armor, PlayerHealth.maxArmor);
    health.reset();
    expect(health.armor, 0);
  });

  test('вспышка урона гаснет', () {
    final health = PlayerHealth()..takeDamage(10);
    health.update(1.0);
    expect(health.damageFlash, 0);
  });
}
