import 'package:vector_math/vector_math.dart' as vm;

/// An authored facade recipe tied to a mapped building, not a surveyed facade.
class FacadeProfile {
  FacadeProfile.fromJson(Map<String, dynamic> json)
    : x = (json['center'][0] as num).toDouble(),
      z = (json['center'][1] as num).toDouble(),
      style = (json['style'] as num).toDouble(),
      bay = (json['bayWidth'] as num).toDouble(),
      variation = (json['variation'] as num).toDouble(),
      tint = vm.Vector4(
        (json['wallColor'][0] as num).toDouble(),
        (json['wallColor'][1] as num).toDouble(),
        (json['wallColor'][2] as num).toDouble(),
        1,
      ),
      entrance = vm.Vector4(
        (json['front'][0] as num).toDouble(),
        (json['front'][1] as num).toDouble(),
        (json['front'][2] as num).toDouble(),
        (json['front'][3] as num).toDouble(),
      );
  final double x, z, style, bay, variation;
  final vm.Vector4 tint, entrance;
  bool matches(vm.Aabb3 bounds) {
    final dx = (bounds.min.x + bounds.max.x) / 2 - x,
        dz = (bounds.min.z + bounds.max.z) / 2 - z;
    return dx * dx + dz * dz < 1;
  }
}
