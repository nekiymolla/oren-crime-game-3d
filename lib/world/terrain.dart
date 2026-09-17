import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Плоский участок земли — подложка везде, где OSM не размечает
/// поверхность (см. district_streamer.dart и filter_oversized_ways.py: даже
/// с landuse/natural большая часть реального района всё равно ничем не
/// покрыта). Цвет — под траву, а не нейтральный бетонный серый: прошлый
/// (0.16, 0.18, 0.16) визуально читался как серый — R≈G≈B слишком близко.
Node buildPlaceholderGround({required double sizeMeters}) {
  final geometry = PlaneGeometry(width: sizeMeters, depth: sizeMeters);
  final material = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.24, 0.34, 0.14, 1.0)
    ..roughnessFactor = 0.95
    ..metallicFactor = 0.0;
  return Node(mesh: Mesh(geometry, material));
}
