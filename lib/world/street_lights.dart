import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;
import 'city_map.dart';

/// A fixed pool lights the nearest mapped/inferred lamp positions. Meshes stream
/// with district chunks; we never allocate a light for every pole in the city.
class StreetLights {
  StreetLights(this.map) {
    for (var i = 0; i < 8; i++) {
      final light = SpotLight(
        color: vm.Vector3(1, .79, .52),
        intensity: 0,
        range: 22,
        innerConeAngle: .65,
        outerConeAngle: 1.1,
      );
      final child = Node()..addComponent(SpotLightComponent(light));
      node.add(child);
      _nodes.add(child);
      _lights.add(light);
    }
  }
  final CityMap map;
  final node = Node(name: 'Street lighting');
  final List<Node> _nodes = [];
  final List<SpotLight> _lights = [];
  final Map<Node, List<PhysicallyBasedMaterial>> _lenses = {};
  List<CityFixture> selected = [];
  vm.Vector3? _lastPosition;
  double _night = -1;
  final Set<String> _chunks = {};
  void registerChunk(Node chunk) {
    _chunks.add(chunk.name);
    _lenses[chunk] = [
      for (final n in chunk.meshNodes)
        for (final p in n.mesh!.primitives)
          if (p.material.name == 'CityLampGlow' &&
              p.material is PhysicallyBasedMaterial)
            p.material as PhysicallyBasedMaterial,
    ];
    _lastPosition = null;
  }

  void unregisterChunk(Node chunk) {
    _chunks.remove(chunk.name);
    _lenses.remove(chunk);
    _lastPosition = null;
  }

  bool update(vm.Vector3 position, double night) {
    if (_lastPosition != null &&
        (position - _lastPosition!).length2 < 25 &&
        (night - _night).abs() < .015) {
      return false;
    }
    _lastPosition = position.clone();
    _night = night;
    final candidates =
        [
          ...map.nearby('lamp', position.x, position.z, radius: 75, limit: 120),
          ...map.nearby(
            'porch_light',
            position.x,
            position.z,
            radius: 18,
            limit: 8,
          ),
        ]..sort(
          (a, b) =>
              (a.distanceSquared(position.x, position.z) *
                      (a.kind == 'porch_light' ? 4 : 1))
                  .compareTo(
                    b.distanceSquared(position.x, position.z) *
                        (b.kind == 'porch_light' ? 4 : 1),
                  ),
        );
    selected = candidates
        .where(
          (f) => _chunks.contains(
            'district:${(f.x / 200).floor()}_${(f.z / 200).floor()}',
          ),
        )
        .take(8)
        .toList();
    for (var i = 0; i < _nodes.length; i++) {
      final active = i < selected.length;
      if (active) _nodes[i].position = selected[i].lightPosition;
      _lights[i].intensity = active
          ? (selected[i].kind == 'porch_light' ? 24 : 110) * night
          : 0;
      _lights[i].range = active && selected[i].kind == 'porch_light' ? 9 : 22;
    }
    for (final materials in _lenses.values) {
      for (final material in materials) {
        material.emissiveFactor = vm.Vector4(
          1 * night * 3,
          .72 * night * 3,
          .34 * night * 3,
          1,
        );
      }
    }
    return true;
  }
}
