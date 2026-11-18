import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;
import '../player/character_motion.dart';

/// Immutable world-space triangle BVH. Built off the UI isolate for each
/// static streamed chunk; dynamic cars keep the engine's mesh raycasts.
class StaticCollisionIndex {
  StaticCollisionIndex._(this.triangles, this._root);
  final Float32List triangles;
  final _Branch _root;

  static Future<StaticCollisionIndex> fromNode(Node root) async {
    final meshes = <_MeshSnapshot>[];
    for (final node in root.meshNodes) {
      if (!node.raycastable || !node.visible) continue;
      for (final primitive in node.mesh!.primitives) {
        if (!primitive.visible ||
            primitive.geometry.primitiveType.name != 'triangle') {
          continue;
        }
        // Pinned flutter_scene 0.23 CPU layout; covered by importer parity QA.
        // ignore: invalid_use_of_internal_member
        final data = primitive.geometry.cpuMeshData;
        if (data.vertexCount == 0) continue;
        final positions = data.positions, vertices = data.vertices;
        if (positions == null && vertices == null) continue;
        final stride = vertices == null
            ? 0
            : vertices.lengthInBytes ~/ data.vertexCount;
        if (positions == null && stride != 72 && stride != 104) continue;
        final indices = data.indices;
        final count = indices == null ? data.vertexCount : data.indexCount;
        if (count == 0) continue;
        final indexBytes = data.indexType.name == 'int16' ? 2 : 4;
        meshes.add(
          _MeshSnapshot(
            positions,
            vertices,
            indices,
            stride,
            count,
            indexBytes,
            Float64List.fromList(node.globalTransform.storage),
          ),
        );
      }
    }
    return compute(_buildMeshes, meshes);
  }

  static StaticCollisionIndex _buildMeshes(List<_MeshSnapshot> meshes) {
    final values = <double>[];
    for (final m in meshes) {
      final transform = vm.Matrix4.fromList(m.transform);
      for (var i = 0; i + 2 < m.count; i += 3) {
        for (var j = 0; j < 3; j++) {
          final indices = m.indices;
          final k = indices == null
              ? i + j
              : m.indexBytes == 2
              ? indices.getUint16((i + j) * 2, Endian.little)
              : indices.getUint32((i + j) * 4, Endian.little);
          final positions = m.positions, vertices = m.vertices;
          final p = positions != null
              ? vm.Vector3(
                  positions[k * 3],
                  positions[k * 3 + 1],
                  positions[k * 3 + 2],
                )
              : vm.Vector3(
                  vertices!.getFloat32(k * m.stride, Endian.little),
                  vertices.getFloat32(k * m.stride + 4, Endian.little),
                  vertices.getFloat32(k * m.stride + 8, Endian.little),
                );
          transform.transform3(p);
          values.addAll([p.x, p.y, p.z]);
        }
      }
    }
    return build(Float32List.fromList(values));
  }

  static StaticCollisionIndex build(Float32List triangles) {
    final order = List<int>.generate(triangles.length ~/ 9, (i) => i);
    _Branch partition(List<int> ids) {
      final lo = [double.infinity, double.infinity, double.infinity];
      final hi = [
        double.negativeInfinity,
        double.negativeInfinity,
        double.negativeInfinity,
      ];
      for (final i in ids) {
        for (var v = 0; v < 3; v++) {
          for (var axis = 0; axis < 3; axis++) {
            final x = triangles[i * 9 + v * 3 + axis];
            lo[axis] = math.min(lo[axis], x);
            hi[axis] = math.max(hi[axis], x);
          }
        }
      }
      if (ids.length <= 12) return _Branch(lo, hi, ids, null, null);
      var axis = 0;
      for (var a = 1; a < 3; a++) {
        if (hi[a] - lo[a] > hi[axis] - lo[axis]) axis = a;
      }
      double center(int id) =>
          triangles[id * 9 + axis] +
          triangles[id * 9 + axis + 3] +
          triangles[id * 9 + axis + 6];
      ids.sort((a, b) => center(a).compareTo(center(b)));
      final mid = ids.length ~/ 2;
      return _Branch(
        lo,
        hi,
        const [],
        partition(ids.sublist(0, mid)),
        partition(ids.sublist(mid)),
      );
    }

    return StaticCollisionIndex._(triangles, partition(order));
  }

  CharacterRayHit? cast(vm.Vector3 origin, vm.Vector3 direction, double reach) {
    var nearest = reach;
    vm.Vector3? normal;
    bool intersects(_Branch b) {
      var near = 0.0, far = nearest;
      for (var a = 0; a < 3; a++) {
        final d = direction[a], o = origin[a];
        if (d.abs() < 1e-12) {
          if (o < b.lo[a] || o > b.hi[a]) return false;
          continue;
        }
        var t0 = (b.lo[a] - o) / d, t1 = (b.hi[a] - o) / d;
        if (t0 > t1) {
          final t = t0;
          t0 = t1;
          t1 = t;
        }
        near = math.max(near, t0);
        far = math.min(far, t1);
        if (near > far) return false;
      }
      return true;
    }

    void visit(_Branch b) {
      if (!intersects(b)) return;
      if (b.left != null) {
        visit(b.left!);
        visit(b.right!);
        return;
      }
      final t = triangles;
      for (final id in b.ids) {
        final i = id * 9;
        final ax = t[i], ay = t[i + 1], az = t[i + 2];
        final ex = t[i + 3] - ax, ey = t[i + 4] - ay, ez = t[i + 5] - az;
        final fx = t[i + 6] - ax, fy = t[i + 7] - ay, fz = t[i + 8] - az;
        final px = direction.y * fz - direction.z * fy,
            py = direction.z * fx - direction.x * fz,
            pz = direction.x * fy - direction.y * fx;
        final det = ex * px + ey * py + ez * pz;
        if (det.abs() < 1e-9) continue;
        final inv = 1 / det,
            sx = origin.x - ax,
            sy = origin.y - ay,
            sz = origin.z - az;
        final u = (sx * px + sy * py + sz * pz) * inv;
        if (u < 0 || u > 1) continue;
        final qx = sy * ez - sz * ey,
            qy = sz * ex - sx * ez,
            qz = sx * ey - sy * ex;
        final v =
            (direction.x * qx + direction.y * qy + direction.z * qz) * inv;
        if (v < 0 || u + v > 1) continue;
        final distance = (fx * qx + fy * qy + fz * qz) * inv;
        if (distance < 0 || distance > nearest) continue;
        nearest = distance;
        normal = vm.Vector3(
          ey * fz - ez * fy,
          ez * fx - ex * fz,
          ex * fy - ey * fx,
        )..normalize();
        if (normal!.dot(direction) > 0) normal!.negate();
      }
    }

    if (reach <= 0 || triangles.isEmpty) return null;
    visit(_root);
    return normal == null
        ? null
        : CharacterRayHit(distance: nearest, normal: normal!);
  }
}

class _Branch {
  _Branch(this.lo, this.hi, this.ids, this.left, this.right);
  final List<double> lo, hi;
  final List<int> ids;
  final _Branch? left, right;
}

class _MeshSnapshot {
  _MeshSnapshot(
    this.positions,
    this.vertices,
    this.indices,
    this.stride,
    this.count,
    this.indexBytes,
    this.transform,
  );
  final Float32List? positions;
  final ByteData? vertices, indices;
  final int stride, count, indexBytes;
  final Float64List transform;
}
