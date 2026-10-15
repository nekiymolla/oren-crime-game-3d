import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'character_animation.dart';

/// Один персонаж на сцене: клон модели из [CharacterLibrary] со своим
/// скелетом и плавными переходами между клипами.
///
/// На узле держатся только нужные сейчас клипы — текущий и затухающие:
/// AnimationPlayer движка считает КАЖДЫЙ зарегистрированный клип каждый
/// кадр, даже с нулевым весом, так что держать все 9 клипов на каждом из
/// ~25 персонажей было бы пустой тратой CPU. Скрытый узел ([visible] =
/// false) движок не анимирует вовсе — далёких персонажей прячем.
class CharacterModel {
  CharacterModel(Node model, Iterable<Animation> animations)
    : _model = model,
      _animations = {for (final a in animations) a.name: a} {
    // Импорт .glb переворачивает Z (см. PROGRESS.md), и лицо модели
    // оказывается на -Z — разворачиваем, чтобы снаружи "вперёд" было +Z,
    // как у курса (yaw) пешеходов и игрока.
    model.rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), math.pi);
    node.add(model);
  }

  /// Корень персонажа: его двигают и поворачивают (вперёд — локальная +Z).
  final Node node = Node();

  /// Сама модель со скелетом — на ней живут клипы.
  final Node _model;

  final Map<String, Animation> _animations;
  final Map<CharacterAnim, AnimationClip> _clips = {};
  CharacterAnim? _current;
  double _fadeSeconds = 0.2;

  CharacterAnim? get current => _current;

  bool get visible => node.visible;
  set visible(bool value) => node.visible = value;

  /// Длительность клипа [anim] в секундах (0 — клипа нет в модели).
  double durationOf(CharacterAnim anim) => _animations[anim.clipName]?.endTime ?? 0.0;

  /// Неповторяющийся текущий клип (удар, выстрел) доигран до конца.
  bool get currentFinished {
    final clip = _clips[_current];
    return clip == null || (!clip.loop && !clip.playing);
  }

  /// Перейти на [anim] за [fadeSeconds] со скоростью [rate]. Повторный вызов
  /// с тем же клипом только меняет скорость (его зовут каждый кадр);
  /// [restart] — проиграть заново с начала (повторный выстрел).
  void play(CharacterAnim anim, {double rate = 1.0, double fadeSeconds = 0.2, bool restart = false}) {
    if (anim == _current && !restart) {
      _clips[anim]?.playbackTimeScale = rate;
      return;
    }
    final firstClip = _clips.isEmpty;
    _current = anim;
    _fadeSeconds = fadeSeconds;
    var clip = _clips[anim];
    if (clip == null) {
      final animation = _animations[anim.clipName];
      if (animation == null) return;
      clip = _model.createAnimationClip(animation)
        ..loop = anim.loops
        ..weight = firstClip || fadeSeconds <= 0 ? 1.0 : 0.0;
      _clips[anim] = clip;
      // Разные персонажи с одним клипом не должны шагать в ногу.
      if (anim.loops && !restart) clip.seek(_phase * animation.endTime);
    }
    if (restart || !anim.loops) clip.seek(0);
    clip
      ..playbackTimeScale = rate
      ..play();
    if (fadeSeconds <= 0) _snapToCurrent();
  }

  /// Сдвиг фазы повторяющихся клипов — свой у каждого персонажа.
  late final double _phase = math.Random(identityHashCode(this)).nextDouble();

  /// Зовётся каждый кадр: веса текущего клипа растут, остальных — гаснут;
  /// погасшие снимаются с узла.
  void update(double dt) {
    final current = _current;
    if (current == null) return;
    final step = _fadeSeconds <= 0 ? 1.0 : dt / _fadeSeconds;
    var othersWeight = 0.0;
    final faded = <CharacterAnim>[];
    _clips.forEach((anim, clip) {
      if (anim == current) return;
      clip.weight -= step;
      if (clip.weight <= 0.0) {
        faded.add(anim);
      } else {
        othersWeight += clip.weight;
      }
    });
    for (final anim in faded) {
      _model.removeAnimationClip(_clips.remove(anim)!);
    }
    final clip = _clips[current];
    if (clip == null) return;
    // Сумма весов держится на 1: иначе движок домешивает T-позу (bind pose).
    clip.weight = math.max(clip.weight + step, 1.0 - othersWeight);
  }

  void _snapToCurrent() {
    final current = _current;
    for (final anim in _clips.keys.where((a) => a != current).toList()) {
      _model.removeAnimationClip(_clips.remove(anim)!);
    }
    _clips[current]?.weight = 1.0;
  }
}
