import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'neon_sign_painter.dart';

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

/// Высота панели вывески (ширина — из данных, [NeonSign.width]); пропорция
/// совпадает с текстурой 512x128 (см. neon_sign_painter.dart).
double neonPanelHeight(double width) => width / 4.0;

/// Надписи вывесок — обычный оренбургский первый этаж.
const List<String> neonWords = [
  'ПРОДУКТЫ',
  'АПТЕКА',
  'БАР',
  'КАФЕ',
  'ШАУРМА',
  '24 ЧАСА',
  'ЛОМБАРД',
  'КЛУБ',
  'ОТЕЛЬ',
  'ПИВО',
  'ЦВЕТЫ',
  'СУШИ',
  'КИНО',
  'САЛОН',
];

/// Что написано на вывеске номер [index] — без движка, проверяется тестом:
/// соседние по списку вывески не повторяют надпись.
String neonSignText(int index) => neonWords[(index * 5 + 3) % neonWords.length];

/// Вывески на сцене: панели с надписью-неонкой (своя текстура на вывеску,
/// unlit с прозрачностью — ночью ярче порога bloom), пятно света на
/// асфальте перед вывеской и ореол на стене (один InstancedMesh). Днём
/// неон едва тлеет, в сумерках загорается; часть вывесок изредка мигает.
class NeonSignsView {
  NeonSignsView._(this.signs, this._panels, this.glows, this._random) {
    for (var i = 0; i < signs.length; i++) {
      _flicker.add(_random.nextDouble() < 0.18);
    }
  }

  static Future<NeonSignsView> build(List<NeonSign> signs, {Material? glowMaterial, math.Random? random}) async {
    final panels = <Node>[];
    final materials = <UnlitMaterial>[];
    for (var i = 0; i < signs.length; i++) {
      final sign = signs[i];
      final c = neonPalette[sign.color % neonPalette.length];
      final image = await paintNeonSign(
        neonSignText(i),
        Color.from(alpha: 1, red: c.x, green: c.y, blue: c.z),
        framed: sign.variant % 2 == 0,
      );
      final texture = await Texture2D.fromImage(image);
      image.dispose();
      final material = UnlitMaterial(colorTexture: texture)
        ..alphaMode = AlphaMode.blend
        ..baseColorFactor = vm.Vector4(0.15, 0.15, 0.15, 1)
        // Плоскость, повёрнутая на стену, показывает текстуру зеркально —
        // отражаем U обратно.
        ..baseColorTextureTransform = TextureTransform(offset: vm.Vector2(1, 0), scale: vm.Vector2(-1, 1));
      materials.add(material);
      final rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), sign.yaw);
      // Плоскость движка лежит в XZ лицом вверх: ставим её на стену лицом
      // к улице.
      final panel = Node(
        mesh: Mesh(PlaneGeometry(width: sign.width, depth: neonPanelHeight(sign.width)), material),
      )
        ..position = sign.wallPoint + sign.normal * 0.14 + vm.Vector3(0, neonSignHeight, 0)
        ..rotation = rotation * vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2)
        ..castsShadows = false;
      panels.add(panel);
    }

    InstancedMesh? glows;
    if (glowMaterial != null) {
      glows = InstancedMesh(geometry: PlaneGeometry(), material: glowMaterial);
      for (final sign in signs) {
        final rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), sign.yaw);
        final center = sign.wallPoint + sign.normal * 0.12 + vm.Vector3(0, neonSignHeight, 0);
        // Пятно на асфальте/тротуаре перед вывеской — "отражение" неона.
        glows.addInstance(
          vm.Matrix4.compose(
            sign.wallPoint + sign.normal * 2.6 + vm.Vector3(0, 0.03, 0),
            rotation,
            vm.Vector3(sign.width * 2.2, 1, 5.0),
          ),
          color: vm.Vector4(0, 0, 0, 0),
        );
        // Ореол на стене вокруг вывески.
        glows.addInstance(
          vm.Matrix4.compose(
            center - sign.normal * 0.07,
            rotation * vm.Quaternion.axisAngle(vm.Vector3(1, 0, 0), math.pi / 2),
            vm.Vector3(sign.width * 1.8, 1, 2.4),
          ),
          color: vm.Vector4(0, 0, 0, 0),
        );
      }
    }
    return NeonSignsView._(signs, [for (var i = 0; i < panels.length; i++) (panels[i], materials[i])], glows, random ?? math.Random());
  }

  final List<NeonSign> signs;
  final List<(Node, UnlitMaterial)> _panels;
  final InstancedMesh? glows;
  final math.Random _random;
  final List<bool> _flicker = [];
  double _appliedOn = -1;
  double _time = 0;

  /// Яркость неона ночью (линейный HDR — выше порога bloom).
  static const double _neonGlow = 3.0;
  static const double _groundGlowAlpha = 0.35;
  static const double _wallGlowAlpha = 0.3;

  Node buildNode() {
    final node = Node();
    for (final (panel, _) in _panels) {
      node.add(panel);
    }
    final glowMesh = glows;
    if (glowMesh != null) node.addComponent(InstancedMeshComponent(glowMesh));
    return node;
  }

  /// [nightFactor]/[goldenHour] — из суточного цикла: неон загорается в
  /// сумерках, днём едва тлеет.
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
        if (phase > 1.75) level *= 0.12;
      }
      final glow = 0.15 + (_neonGlow - 0.15) * level;
      _panels[i].$2.baseColorFactor = vm.Vector4(glow, glow, glow, 1);
      final glowMesh = glows;
      if (glowMesh != null) {
        final c = neonPalette[signs[i].color % neonPalette.length];
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
