import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'player_shooting.dart';

/// Видимая часть выстрела: вспышка у ствола (с настоящим светом —
/// ночью освещает улицу), трассеры пуль, искры от стен и кровь от
/// попаданий в людей. Всё из заранее созданных пулов узлов — на выстрел
/// ничего не создаётся (геометрия заводит буферы на GPU).
class WeaponEffectsView {
  static const int _poolSize = 8;
  static const double _flashSeconds = 0.05;
  static const double _tracerSeconds = 0.06;
  static const double _impactSeconds = 0.25;

  final Node root = Node();
  late final Node _flash;
  late final PointLight _flashLight;
  final List<_Timed> _tracers = [];
  final List<_Timed> _sparks = [];
  final List<_Timed> _blood = [];
  double _flashLeft = 0.0;
  int _nextTracer = 0;
  int _nextSpark = 0;
  int _nextBlood = 0;

  static PhysicallyBasedMaterial _glow(vm.Vector4 color, double strength) => PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0, 0, 0, 1)
    ..emissiveFactor = color
    ..emissiveStrength = strength;

  Node buildNode() {
    final flashMaterial = _glow(vm.Vector4(1.0, 0.75, 0.35, 1.0), 12.0);
    _flashLight = PointLight(color: vm.Vector3(1.0, 0.7, 0.35), intensity: 0.0, range: 9.0);
    _flash = Node(mesh: Mesh(SphereGeometry(radius: 0.09, segments: 8, rings: 6), flashMaterial))
      ..addComponent(PointLightComponent(_flashLight))
      ..visible = false;
    root.add(_flash);

    // Трассер — вытянутый вдоль локальной +Z брусок единичной длины.
    final tracerGeometry = CuboidGeometry(vm.Vector3(0.025, 0.025, 1.0));
    final tracerMaterial = _glow(vm.Vector4(1.0, 0.85, 0.5, 1.0), 6.0);
    final impactGeometry = SphereGeometry(radius: 0.08, segments: 8, rings: 6);
    final sparkMaterial = _glow(vm.Vector4(1.0, 0.8, 0.45, 1.0), 8.0);
    final bloodMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = vm.Vector4(0.45, 0.02, 0.02, 1.0)
      ..roughnessFactor = 0.4;
    for (var i = 0; i < _poolSize; i++) {
      _tracers.add(_Timed(Node(mesh: Mesh(tracerGeometry, tracerMaterial))..visible = false));
      _sparks.add(_Timed(Node(mesh: Mesh(impactGeometry, sparkMaterial))..visible = false));
      _blood.add(_Timed(Node(mesh: Mesh(impactGeometry, bloodMaterial))..visible = false));
    }
    for (final effect in [..._tracers, ..._sparks, ..._blood]) {
      root.add(effect.node);
    }
    return root;
  }

  void showShot(ShotOutcome shot) {
    _flash
      ..position = shot.muzzle
      ..visible = true;
    _flashLight.intensity = 6.0;
    _flashLeft = _flashSeconds;

    for (final bullet in shot.bullets) {
      final tracer = _tracers[_nextTracer];
      _nextTracer = (_nextTracer + 1) % _poolSize;
      final delta = bullet.end - shot.muzzle;
      final length = delta.length;
      if (length > 0.3) {
        tracer.node.localTransform = vm.Matrix4.compose(
          shot.muzzle + delta * 0.5,
          vm.Quaternion.fromTwoVectors(vm.Vector3(0, 0, 1), delta / length),
          vm.Vector3(1, 1, length),
        );
        tracer.show(_tracerSeconds);
      }

      if (bullet.impact == BulletImpact.none) continue;
      final pool = bullet.impact == BulletImpact.flesh ? _blood : _sparks;
      final index = bullet.impact == BulletImpact.flesh ? _nextBlood : _nextSpark;
      if (bullet.impact == BulletImpact.flesh) {
        _nextBlood = (_nextBlood + 1) % _poolSize;
      } else {
        _nextSpark = (_nextSpark + 1) % _poolSize;
      }
      pool[index]
        ..node.localTransform = vm.Matrix4.translation(bullet.end)
        ..show(_impactSeconds);
    }
  }

  void update(double dt) {
    if (_flashLeft > 0.0) {
      _flashLeft -= dt;
      if (_flashLeft <= 0.0) {
        _flash.visible = false;
        _flashLight.intensity = 0.0;
      }
    }
    for (final tracer in _tracers) {
      tracer.tick(dt);
    }
    // Искры и кровь чуть разлетаются — растут, пока видны.
    for (final impact in [..._sparks, ..._blood]) {
      if (!impact.tick(dt)) continue;
      final age = 1.0 - impact.left / _impactSeconds;
      final position = impact.node.localTransform.getTranslation();
      impact.node.localTransform = vm.Matrix4.compose(position, vm.Quaternion.identity(), vm.Vector3.all(0.6 + age * 1.4));
    }
  }
}

class _Timed {
  _Timed(this.node);

  final Node node;
  double left = 0.0;

  void show(double seconds) {
    left = seconds;
    node.visible = true;
  }

  /// true — ещё виден.
  bool tick(double dt) {
    if (left <= 0.0) return false;
    left -= dt;
    if (left <= 0.0) {
      node.visible = false;
      return false;
    }
    return true;
  }
}
