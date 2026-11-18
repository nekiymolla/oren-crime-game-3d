import 'package:crime_oren/characters/character_animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('walk/run transition preserves the stride phase', () {
    expect(
      gaitTransitionPhase(CharacterAnim.walk, CharacterAnim.run, .8, 1.0),
      .8,
    );
    expect(
      gaitTransitionPhase(CharacterAnim.run, CharacterAnim.walk, 1.25, .5),
      .5,
    );
    expect(
      gaitTransitionPhase(CharacterAnim.idle, CharacterAnim.walk, .8, 1.0),
      isNull,
    );
  });
  test('locomotion thresholds do not flicker at a gait boundary', () {
    expect(
      locomotionAnim(speed: 2.5, previous: CharacterAnim.run).anim,
      CharacterAnim.run,
    );
    expect(
      locomotionAnim(speed: 2.5, previous: CharacterAnim.walk).anim,
      CharacterAnim.walk,
    );
    expect(
      locomotionAnim(speed: .2, previous: CharacterAnim.walk).anim,
      CharacterAnim.walk,
    );
    expect(
      locomotionAnim(speed: .2, previous: CharacterAnim.idle).anim,
      CharacterAnim.idle,
    );
  });

  test('стоит, идёт, бежит — по скорости', () {
    expect(locomotionAnim(speed: 0.0).anim, CharacterAnim.idle);
    expect(locomotionAnim(speed: 1.3).anim, CharacterAnim.walk);
    expect(locomotionAnim(speed: 4.5).anim, CharacterAnim.run);
  });

  test('лежачий — клип смерти, даже если отлетает со скоростью', () {
    expect(locomotionAnim(speed: 6.0, lying: true).anim, CharacterAnim.death);
  });

  test('целится: стоя — пистолет наизготовку, на бегу — бег со стрельбой', () {
    expect(locomotionAnim(speed: 0.0, aiming: true).anim, CharacterAnim.aim);
    expect(
      locomotionAnim(speed: 5.0, aiming: true).anim,
      CharacterAnim.runShoot,
    );
  });

  test('шаг подстраивается под скорость, чтобы ноги не скользили', () {
    final slow = locomotionAnim(speed: 0.9);
    final fast = locomotionAnim(speed: 2.0);
    expect(slow.rate, lessThan(1.0));
    expect(fast.rate, greaterThan(1.0));
    expect(locomotionAnim(speed: walkClipSpeed).rate, closeTo(1.0, 1e-9));
  });
  test('медленный аналоговый шаг не ускоряет ноги до половины темпа', () {
    final slow = locomotionAnim(speed: walkClipSpeed * 0.3);
    expect(slow.anim, CharacterAnim.walk);
    expect(slow.rate, closeTo(0.3, 1e-6));
  });
}
