import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Неоновая вывеска на фасаде (assets/data/neon_signs.json — расставлены
/// пайплайном place_neon_signs.py + filter_neon_signs.mjs на стенах вдоль
/// крупных улиц, сверено с 3D-геометрией).
class NeonSign {
  const NeonSign({
    required this.x,
    required this.z,
    required this.normalX,
    required this.normalZ,
    required this.width,
    required this.color,
    required this.variant,
  });

  factory NeonSign.fromJson(Map<String, dynamic> json) => NeonSign(
    x: (json['x'] as num).toDouble(),
    z: (json['z'] as num).toDouble(),
    normalX: (json['nx'] as num).toDouble(),
    normalZ: (json['nz'] as num).toDouble(),
    width: (json['width'] as num).toDouble(),
    color: json['color'] as int,
    variant: json['variant'] as int,
  );

  /// Точка на стене (низ — земля) и нормаль стены наружу, к улице.
  final double x;
  final double z;
  final double normalX;
  final double normalZ;
  final double width;

  /// Индекс в [neonPalette] и вариант раскладки трубок (см. [neonTubes]).
  final int color;
  final int variant;

  vm.Vector3 get wallPoint => vm.Vector3(x, 0, z);
  vm.Vector3 get normal => vm.Vector3(normalX, 0, normalZ);

  /// Курс "лицом к улице" (та же конвенция, что у машин: atan2(x, z)).
  double get yaw => math.atan2(normalX, normalZ);
}

Future<List<NeonSign>> loadNeonSigns() async {
  final raw = await rootBundle.loadString('assets/data/neon_signs.json');
  final json = jsonDecode(raw) as Map<String, dynamic>;
  return [for (final s in json['signs'] as List) NeonSign.fromJson(s as Map<String, dynamic>)];
}

/// Палитра в духе Вайс-Сити: розовый, бирюзовый, фиолетовый, оранжевый,
/// салатовый. Пайплайн выбирает индекс 0..4.
final List<vm.Vector3> neonPalette = [
  vm.Vector3(1.0, 0.18, 0.62),
  vm.Vector3(0.1, 0.9, 1.0),
  vm.Vector3(0.62, 0.25, 1.0),
  vm.Vector3(1.0, 0.45, 0.1),
  vm.Vector3(0.35, 1.0, 0.35),
];

/// Высота центра вывески над землёй — над витриной первого этажа.
const double neonSignHeight = 3.3;
const double _tube = 0.06;
const double _signHeight = 0.9;

/// Одна трубка вывески в её локальных координатах: x — вдоль стены, y —
/// вверх; [length] вдоль [vertical]-оси.
typedef NeonTube = ({double x, double y, double length, bool vertical});

/// Раскладка трубок по варианту — без движка, проверяется тестом:
/// 0 — рамка со строкой "текста", 1 — двойная линия с засечками,
/// 2 — рамка с тремя "буквами".
List<NeonTube> neonTubes(double width, int variant) {
  final halfW = width / 2;
  const halfH = _signHeight / 2;
  final frame = <NeonTube>[
    (x: 0, y: halfH, length: width, vertical: false),
    (x: 0, y: -halfH, length: width, vertical: false),
    (x: -halfW, y: 0, length: _signHeight, vertical: true),
    (x: halfW, y: 0, length: _signHeight, vertical: true),
  ];
  return switch (variant % 3) {
    0 => [...frame, (x: 0, y: 0, length: width * 0.7, vertical: false)],
    1 => [
      (x: 0, y: 0.18, length: width, vertical: false),
      (x: 0, y: -0.18, length: width * 0.8, vertical: false),
      (x: -halfW, y: 0.06, length: 0.3, vertical: true),
      (x: halfW, y: 0.06, length: 0.3, vertical: true),
    ],
    _ => [
      ...frame,
      for (final f in const [-0.25, 0.0, 0.25]) (x: width * f, y: 0, length: _signHeight * 0.55, vertical: true),
    ],
  };
}

/// Вывески на сцене: трубки (unlit, ярче порога bloom — светятся ореолом),
/// пятно света на асфальте перед вывеской и ореол на стене. Три
/// InstancedMesh на весь город. Днём трубки тёмные стеклянные, в сумерках
/// загораются; пара вывесок изредка мигает.
class NeonSignsView {
  NeonSignsView(this.signs, {Material? glowMaterial, math.Random? random})
    : _random = random ?? math.Random(),
      tubes = InstancedMesh(
        geometry: CuboidGeometry(vm.Vector3(1, 1, 1)),
        material: UnlitMaterial()..baseColorFactor = vm.Vector4(1, 1, 1, 1),
      ),
      glows = glowMaterial == null ? null : InstancedMesh(geometry: PlaneGeometry(), material: glowMaterial) {
    for (var i = 0; i < signs.length; i++) {
      final sign = signs[i];
      final rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), sign.yaw);
      // Локальная x вывески после поворота — вдоль стены.
      final along = rotation.rotated(vm.Vector3(1, 0, 0));
      final center = sign.wallPoint + sign.normal * 0.12 + vm.Vector3(0, neonSignHeight, 0);
      final first = tubes.instanceCount;
      for (final t in neonTubes(sign.width, sign.variant)) {
        final scale = t.vertical ? vm.Vector3(_tube, t.length, _tube) : vm.Vector3(t.length, _tube, _tube);
        tubes.addInstance(
          vm.Matrix4.compose(center + along * t.x + vm.Vector3(0, t.y, 0), rotation, scale),
          color: vm.Vector4(0, 0, 0, 1),
        );
      }
      _tubeRanges.add((first, tubes.instanceCount));

      final glowMesh = glows;
      if (glowMesh != null) {
        // Пятно на асфальте/тротуаре перед вывеской — "отражение" неона.
        glowMesh.addInstance(
          vm.Matrix4.compose(
            sign.wallPoint + sign.normal * 2.6 + vm.Vector3(0, 0.03, 0),
            rotation,
            vm.Vector3(sign.width * 2.2, 1, 5.0),
          ),
          color: vm.Vector4(0, 0, 0, 0),
        );
        // Ореол на стене вокруг вывески (плоскость XZ, повёрнутая лицом к
        // улице).
        glowMesh.addInstance(
          vm.Matrix4.compose(
            center - sign.normal * 0.07,
            rotation * vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
            vm.Vector3(sign.width * 2.0, 1, 2.6),
          ),
          color: vm.Vector4(0, 0, 0, 0),
        );
      }
      _flicker.add(_random.nextDouble() < 0.15);
    }
  }

  final List<NeonSign> signs;
  final InstancedMesh tubes;
  final InstancedMesh? glows;
  final math.Random _random;
  final List<(int, int)> _tubeRanges = [];
  final List<bool> _flicker = [];
  double _appliedOn = -1;
  double _time = 0;

  /// Яркость трубки ночью (линейный HDR — выше порога bloom).
  static const double _tubeGlow = 3.2;
  static const double _groundGlowAlpha = 0.35;
  static const double _wallGlowAlpha = 0.35;

  Node buildNode() {
    final node = Node()..addComponent(InstancedMeshComponent(tubes));
    final glowMesh = glows;
    if (glowMesh != null) node.addComponent(InstancedMeshComponent(glowMesh));
    return node;
  }

  /// [nightFactor]/[goldenHour] — из суточного цикла: неон загорается в
  /// сумерках, днём трубки тёмные.
  void update(double dt, {required double nightFactor, required double goldenHour}) {
    _time += dt;
    final on = _smoothstep(0.15, 0.6, math.max(nightFactor, goldenHour * 0.7));
    final anyFlicker = on > 0.05 && _flicker.contains(true);
    if ((on - _appliedOn).abs() < 0.01 && !anyFlicker) return;
    _appliedOn = on;

    for (var i = 0; i < signs.length; i++) {
      // Мигание: редкие короткие провалы, как у старой неонки.
      var level = on;
      if (_flicker[i] && on > 0.05) {
        final phase = math.sin(_time * 1.7 + i * 3.1) + math.sin(_time * 13.0 + i);
        if (phase > 1.75) level *= 0.15;
      }
      final c = neonPalette[signs[i].color % neonPalette.length];
      // Днём — тёмное цветное стекло, ночью — ярче порога bloom.
      final tube = c * (0.12 + (_tubeGlow - 0.12) * level);
      final (first, end) = _tubeRanges[i];
      for (var t = first; t < end; t++) {
        tubes.setInstanceColor(t, vm.Vector4(tube.x, tube.y, tube.z, 1));
      }
      final glowMesh = glows;
      if (glowMesh != null) {
        glowMesh.setInstanceColor(i * 2, vm.Vector4(c.x, c.y, c.z, _groundGlowAlpha * level));
        glowMesh.setInstanceColor(i * 2 + 1, vm.Vector4(c.x, c.y, c.z, _wallGlowAlpha * level));
      }
    }
  }

  static double _smoothstep(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}
