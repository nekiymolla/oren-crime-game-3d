import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

import 'traffic_car.dart';
import 'traffic_signals.dart';

/// Где стоит столб светофора въезда: у стоп-линии, справа от полосы, на
/// обочине. Общая функция — та же точка проверяется пайплайном на
/// попадание в дома (см. tools/osm_pipeline/check_road_graph.mjs).
vm.Vector3 signalPolePosition(vm.Vector3 intersectionNode, vm.Vector3 direction) =>
    intersectionNode - direction * signalStopLineBack + rightOf(direction) * signalPoleSideOffset;

/// Насколько столб правее оси дороги, метры: полоса (1.5) плюс обочина.
const double signalPoleSideOffset = 4.0;

/// Светофоры на экране: все столбы, корпуса и лампы района — три
/// InstancedMesh, то есть три draw call на весь город и всего три узла
/// сцены (машина игрока кидает лучи по всему графу сцены — сотни узлов
/// светофоров были бы ей ощутимы). Цвет ламп меняется только в момент
/// переключения фазы.
class TrafficSignalsView {
  TrafficSignalsView(this.signals)
    : poles = InstancedMesh(
        geometry: CylinderGeometry(bottomRadius: 0.08, topRadius: 0.07, height: _poleHeight),
        material: PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.25, 0.26, 0.28, 1.0)
          ..metallicFactor = 0.6
          ..roughnessFactor = 0.5,
      ),
      housings = InstancedMesh(
        geometry: CuboidGeometry(vm.Vector3(0.36, 1.05, 0.28)),
        material: PhysicallyBasedMaterial()
          ..baseColorFactor = vm.Vector4(0.06, 0.06, 0.07, 1.0)
          ..roughnessFactor = 0.7,
      ),
      lamps = InstancedMesh(
        geometry: IcosphereGeometry(radius: 0.12, subdivisions: 1),
        // Unlit: горящая лампа должна светиться и в тени, а цвет каждой
        // задаётся множителем инстанса (белый материал x цвет лампы).
        material: UnlitMaterial()..baseColorFactor = vm.Vector4(1, 1, 1, 1),
      ) {
    final graph = signals.network.graph;
    for (final approach in signals.approaches) {
      final node = graph.nodes[approach.toNodeId]!.toVector3();
      final pole = signalPolePosition(node, approach.direction);
      // Лицом к подъезжающим: "назад" по направлению въезда.
      final facing = -approach.direction;
      final yaw = math.atan2(facing.x, facing.z);
      final rotation = vm.Quaternion.axisAngle(vm.Vector3(0, 1, 0), yaw);

      poles.addInstance(vm.Matrix4.compose(pole + vm.Vector3(0, _poleHeight / 2, 0), rotation, vm.Vector3.all(1)));
      final head = pole + vm.Vector3(0, _headHeight, 0);
      housings.addInstance(vm.Matrix4.compose(head, rotation, vm.Vector3.all(1)));

      final front = head + facing * 0.15;
      final first = lamps.instanceCount;
      for (final dy in const [0.33, 0.0, -0.33]) {
        lamps.addInstance(
          vm.Matrix4.compose(front + vm.Vector3(0, dy, 0), rotation, vm.Vector3.all(1)),
          color: _off,
        );
      }
      _lampStart.add(first);
      _shown.add(null);
    }
  }

  final TrafficSignals signals;
  final InstancedMesh poles;
  final InstancedMesh housings;
  final InstancedMesh lamps;

  /// Индекс первой (красной) лампы каждого въезда и показанный сейчас сигнал.
  final List<int> _lampStart = [];
  final List<SignalLight?> _shown = [];

  static const double _poleHeight = 3.0;
  static const double _headHeight = 3.3;

  static final vm.Vector4 _off = vm.Vector4(0.07, 0.07, 0.07, 1.0);
  static final vm.Vector4 _red = vm.Vector4(1.0, 0.08, 0.05, 1.0);
  static final vm.Vector4 _yellow = vm.Vector4(1.0, 0.7, 0.05, 1.0);
  static final vm.Vector4 _green = vm.Vector4(0.1, 1.0, 0.3, 1.0);

  Node buildNode() => Node()
    ..addComponent(InstancedMeshComponent(poles))
    ..addComponent(InstancedMeshComponent(housings))
    ..addComponent(InstancedMeshComponent(lamps));

  /// Зовётся каждый кадр из Game.tick(): перекрашивает лампы тех въездов,
  /// где сменился сигнал.
  void update() {
    for (var i = 0; i < signals.approaches.length; i++) {
      final light = signals.approaches[i].lightAt(signals.time);
      if (light == _shown[i]) continue;
      _shown[i] = light;
      final start = _lampStart[i];
      lamps.setInstanceColor(start, light == SignalLight.red ? _red : _off);
      lamps.setInstanceColor(start + 1, light == SignalLight.yellow ? _yellow : _off);
      lamps.setInstanceColor(start + 2, light == SignalLight.green ? _green : _off);
    }
  }
}
