import 'dart:math' as math;

/// Здоровье и бронежилет игрока. Чистая логика (проверена тестами):
/// урон сначала принимает бронежилет, потом здоровье; смерть; медленная
/// регенерация здоровья после передышки — на мобильном экране без
/// аптечек иначе любая перестрелка заканчивалась бы смертью. Бронежилет
/// сам не восстанавливается — только подобранный.
class PlayerHealth {
  static const double maxHealth = 100.0;
  static const double maxArmor = 100.0;

  double armor = 0.0;

  /// Changes for every accepted hit, including damage absorbed by armour.
  int get damageRevision => _damageRevision;
  int _damageRevision = 0;

  /// Через сколько секунд без урона начинается регенерация и как быстро.
  static const double regenDelaySeconds = 8.0;
  static const double regenPerSecond = 4.0;

  double health = maxHealth;
  double _secondsSinceDamage = double.infinity;
  double _flash = 0.0;

  bool get isDead => health <= 0.0;

  /// 0..1 — сила красной вспышки по краям экрана после попадания.
  double get damageFlash => _flash;

  /// Возвращает true ровно когда этот урон убил.
  bool takeDamage(double amount) {
    if (isDead || amount <= 0.0) return false;
    _damageRevision++;
    final absorbed = math.min(armor, amount);
    armor -= absorbed;
    health = math.max(0.0, health - (amount - absorbed));
    _secondsSinceDamage = 0.0;
    _flash = math.min(1.0, _flash + 0.35 + amount / 40.0);
    return isDead;
  }

  void update(double dt) {
    _flash = math.max(0.0, _flash - dt * 2.0);
    if (isDead) return;
    _secondsSinceDamage += dt;
    if (_secondsSinceDamage >= regenDelaySeconds && health < maxHealth) {
      health = math.min(maxHealth, health + regenPerSecond * dt);
    }
  }

  /// Подобрал бронежилет: прибавка, не выше [maxArmor].
  void addArmor(double amount) => armor = math.min(maxArmor, armor + amount);

  /// Возрождение: здоровье полное, бронежилет потерян.
  void reset() {
    armor = 0.0;
    health = maxHealth;
    _secondsSinceDamage = double.infinity;
    _flash = 0.0;
  }
}
