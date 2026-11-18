import 'dart:collection';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

class CrushZone {
  CrushZone(this.center, this.normal, this.depth);
  final vm.Vector3 center, normal;
  double depth;
}

/// Localised, bounded plastic dents. CPU/GPU geometry is rebuilt only on an
/// impact, never each frame; source templates and other cars remain untouched.
class VehicleDeformation {
  final zones = <CrushZone>[];
  final Map<Node, List<MeshData>> _original = {};
  final _queued = <Node>{};
  int _revision = 0, appliedRevision = -1;
  double maxDisplacement = 0;
  static final _jobs = Queue<Future<void> Function()>();
  static bool _busy = false;
  static void _pump() {
    if (_busy) return;
    _busy = true;
    Future<void>(() async {
      try {
        while (_jobs.isNotEmpty) {
          try {
            await _jobs.removeFirst()();
          } catch (e) {
            debugPrint('VehicleDeformation failed: $e');
          }
          if (_jobs.isNotEmpty) await SchedulerBinding.instance.endOfFrame;
        }
      } finally {
        _busy = false;
      }
    });
  }

  bool add(vm.Vector3 point, vm.Vector3 normal, double closingSpeed) {
    if (closingSpeed < 2.5) return false;
    final depth = ((closingSpeed - 2) * .024).clamp(.025, .38);
    CrushZone? near;
    for (final z in zones) {
      if ((z.center - point).length2 < 1.4 && z.normal.dot(normal) > .5) {
        near = z;
        break;
      }
    }
    if (near == null && zones.length >= 10) {
      near = zones.reduce(
        (a, b) =>
            (a.center - point).length2 < (b.center - point).length2 ? a : b,
      );
    }
    if (near != null) {
      near.depth = (near.depth + depth * .65).clamp(0, .52);
    } else {
      zones.add(CrushZone(point.clone(), normal.normalized(), depth));
    }
    _revision++;
    return true;
  }

  void apply(Node body, Node car) {
    if (zones.isEmpty || !body.visible || !_queued.add(body)) return;
    _jobs.add(() async {
      final version = _revision;
      final watch = Stopwatch()..start();
      var processed = 0;
      try {
        for (final node in body.meshNodes) {
          if (!body.visible) break;
          final original = _original.putIfAbsent(
            node,
            () => [
              for (final p in node.mesh!.primitives)
                p.geometry.extractMeshData(),
            ],
          );
          for (var i = 0; i < original.length; i++) {
            if (!body.visible) break;
            if (processed > 0 &&
                (processed >= 2 || watch.elapsedMicroseconds > 2000)) {
              await SchedulerBinding.instance.endOfFrame;
              watch.reset();
              processed = 0;
            }
            final invCar = car.globalTransform.clone()..invert();
            final toCar = invCar * node.globalTransform,
                fromCar = toCar.clone()..invert();
            final data = original[i];
            if (data.primitiveType.name != "triangle") continue;
            final positions = Float32List(data.positions.length),
                weights = Float32List(data.vertexCount);
            final colors = Float32List(data.vertexCount * 4);
            for (var v = 0; v < data.vertexCount; v++) {
              final p = toCar.transform3(
                vm.Vector3(
                  data.positions[v * 3],
                  data.positions[v * 3 + 1],
                  data.positions[v * 3 + 2],
                ),
              );
              final changed = deformPoint(p, zones),
                  q = fromCar.transform3(changed.position);
              maxDisplacement = math.max(
                maxDisplacement,
                (changed.position - p).length,
              );
              positions[v * 3] = q.x;
              positions[v * 3 + 1] = q.y;
              positions[v * 3 + 2] = q.z;
              weights[v] = changed.scratch;
              for (var c = 0; c < 3; c++) {
                colors[v * 4 + c] =
                    (data.colors?[v * 4 + c] ?? 1) *
                    (1 - changed.scratch * .42);
              }
              colors[v * 4 + 3] = data.colors?[v * 4 + 3] ?? 1;
            }
            final generated = MeshData.build(
              positions: positions,
              indices: data.indices,
            ).normals!;
            final normals = Float32List.fromList(generated);
            if (data.normals != null) {
              for (var v = 0; v < data.vertexCount; v++) {
                final w = weights[v];
                var length2 = 0.0;
                for (var c = 0; c < 3; c++) {
                  final j = v * 3 + c;
                  normals[j] = data.normals![j] * (1 - w) + generated[j] * w;
                  length2 += normals[j] * normals[j];
                }
                if (w > 0 && length2 > 1e-10) {
                  final inv = 1 / math.sqrt(length2);
                  for (var c = 0; c < 3; c++) {
                    normals[v * 3 + c] *= inv;
                  }
                }
              }
            }
            final mesh = node.mesh!.clone();
            mesh.primitives[i].geometry = MeshGeometry.fromArrays(
              positions: positions,
              normals: normals,
              texCoords: data.texCoords,
              texCoords1: data.texCoords1,
              colors: colors,
              indices: data.indices,
              tangents: data.tangents,
            );
            node.mesh = mesh;
            processed++;
          }
        }
        appliedRevision = version;
      } finally {
        _queued.remove(body);
      }
      if (_revision != version && body.visible) apply(body, car);
    });
    _pump();
  }
}

({vm.Vector3 position, double scratch}) deformPoint(
  vm.Vector3 p,
  List<CrushZone> zones,
) {
  final delta = vm.Vector3.zero();
  var scratch = 0.0;
  for (final zone in zones) {
    final d = p - zone.center;
    final r2 = (d.x * d.x + d.z * d.z + d.y * d.y * .7) / (1.5 * 1.5);
    if (r2 >= 1) continue;
    final falloff = (1 - r2) * (1 - r2);
    delta.addScaled(zone.normal, zone.depth * falloff);
    // Small folded-metal ridge, not a uniform scaling of the whole car.
    delta.y += zone.depth * .22 * falloff * math.sin(math.pi * math.sqrt(r2));
    scratch = math.max(scratch, falloff * (zone.depth / .25).clamp(0, 1));
  }
  final horizontal = math.sqrt(delta.x * delta.x + delta.z * delta.z);
  if (horizontal > .52) {
    delta.x *= .52 / horizontal;
    delta.z *= .52 / horizontal;
  }
  delta.y = delta.y.clamp(-.12, .18);
  return (position: p + delta, scratch: scratch);
}
