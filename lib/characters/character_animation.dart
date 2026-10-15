/// Клипы персонажей (имена — как в assets/models/characters/*_casual.glb,
/// см. tools/assets/prepare_characters.mjs). Чистый Dart без flutter_scene —
/// выбор клипа проверяется юнит-тестом.
enum CharacterAnim {
  idle('Idle'),
  walk('Walk'),
  run('Run'),
  death('Death', loops: false),
  hit('HitRecieve', loops: false),
  aim('Idle_Gun_Pointing'),
  shoot('Gun_Shoot', loops: false),
  runShoot('Run_Shoot'),
  interact('Interact', loops: false);

  const CharacterAnim(this.clipName, {this.loops = true});

  final String clipName;
  final bool loops;
}

/// Скорость, на которую рассчитан клип ходьбы (м/с): при ней ноги не
/// проскальзывают. Быстрее/медленнее — клип ускоряется/замедляется.
const double walkClipSpeed = 1.4;

/// То же для бега.
const double runClipSpeed = 4.2;

/// Медленнее этого персонаж считается стоящим.
const double _idleBelow = 0.25;

/// Быстрее этого — бег вместо шага.
const double _runAbove = 2.6;

/// Что играть персонажу в его состоянии: лежит (убит/сбит) — смерть,
/// целится — оружие наизготовку (на бегу — бег со стрельбой), иначе по
/// скорости — стоит/идёт/бежит. [speed] — горизонтальная скорость, м/с.
/// Возвращает клип и скорость его проигрывания (шаг/бег подстраиваются
/// под реальную скорость, чтобы ноги не скользили).
({CharacterAnim anim, double rate}) locomotionAnim({
  required double speed,
  bool lying = false,
  bool aiming = false,
}) {
  if (lying) return (anim: CharacterAnim.death, rate: 1.0);
  if (aiming) {
    return speed > _runAbove
        ? (anim: CharacterAnim.runShoot, rate: (speed / runClipSpeed).clamp(0.6, 1.6))
        : (anim: CharacterAnim.aim, rate: 1.0);
  }
  if (speed < _idleBelow) return (anim: CharacterAnim.idle, rate: 1.0);
  if (speed > _runAbove) return (anim: CharacterAnim.run, rate: (speed / runClipSpeed).clamp(0.6, 1.6));
  return (anim: CharacterAnim.walk, rate: (speed / walkClipSpeed).clamp(0.5, 1.8));
}
