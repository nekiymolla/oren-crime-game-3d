import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Плоский участок земли для вертикального среза Phase 1. Позже заменяется
/// реальной геометрией квартала, сгенерированной из OSM (см. lib/world).
Node buildPlaceholderGround({required double sizeMeters}) {
  final geometry = PlaneGeometry(width: sizeMeters, depth: sizeMeters);
  final material = PhysicallyBasedMaterial()
    ..baseColorFactor = vm.Vector4(0.16, 0.18, 0.16, 1.0)
    ..roughnessFactor = 0.95
    ..metallicFactor = 0.0;
  return Node(mesh: Mesh(geometry, material));
}
