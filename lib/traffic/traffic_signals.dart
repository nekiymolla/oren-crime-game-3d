import 'dart:math' as math;

import 'package:vector_math/vector_math.dart' as vm;

import '../world/road_graph.dart';
import 'traffic_car.dart';

enum SignalLight { green, yellow, red }

/// Длительности фаз, секунды. Цикл — две группы направлений по очереди:
/// зелёный, жёлтый, все красные (чтобы перекрёсток успел освободиться).
abstract final class SignalTiming {
  static const double green = 12.0;
  static const double yellow = 3.0;
  static const double allRed = 2.0;
  static const double phase = green + yellow + allRed;
  static const double cycle = phase * 2;
}

/// Сколько метров до узла перекрёстка стоп-линия — машина встаёт перед
/// ней, а не посреди пересекаемой дороги.
const double signalStopLineBack = 6.0;

/// Светофорный перекрёсток. Направления делятся на две группы по оси:
/// почти параллельные [referenceAxis] (в обе стороны) едут вместе, поперечные
/// — в другую фазу. Несколько узлов графа вплотную друг к другу (двойной
/// перекрёсток OSM) — один перекрёсток с общим циклом: иначе машина
/// вставала бы посреди него перед вторым светофором.
class SignalizedIntersection {
  SignalizedIntersection({
    required this.nodeIds,
    required this.center,
    required this.referenceAxis,
    required this.offsetSeconds,
  });

  final Set<String> nodeIds;
  final vm.Vector3 center;
  final vm.Vector3 referenceAxis;

  /// Сдвиг цикла — соседние перекрёстки не переключаются синхронно.
  final double offsetSeconds;

  /// Группа направления движения [direction] (0 — вдоль оси, 1 — поперёк).
  int groupOf(vm.Vector3 direction) {
    final along = (direction.x * referenceAxis.x + direction.z * referenceAxis.z).abs();
    return along >= math.cos(math.pi / 4) ? 0 : 1;
  }

  SignalLight lightFor(vm.Vector3 direction, double time) {
    final t = (time + offsetSeconds) % SignalTiming.cycle;
    final activeGroup = t < SignalTiming.phase ? 0 : 1;
    if (groupOf(direction) != activeGroup) return SignalLight.red;
    final inPhase = t % SignalTiming.phase;
    if (inPhase < SignalTiming.green) return SignalLight.green;
    if (inPhase < SignalTiming.green + SignalTiming.yellow) return SignalLight.yellow;
    return SignalLight.red;
  }
}

/// Въезд на светофорный перекрёсток: по ребру [fromNodeId] -> [toNodeId]
/// (узел перекрёстка). Для каждого рисуется свой светофор.
class SignalApproach {
  SignalApproach({required this.intersection, required this.fromNodeId, required this.toNodeId, required this.direction});

  final SignalizedIntersection intersection;
  final String fromNodeId;
  final String toNodeId;

  /// Направление движения по въезду (единичный, горизонтальный).
  final vm.Vector3 direction;

  SignalLight lightAt(double time) => intersection.lightFor(direction, time);
}

/// Все светофоры района и общее время их цикла. Чистая логика без
/// flutter_scene — проверяется юнит-тестами, рисует SignalsView.
///
/// Светофоры ставятся только там, где они нужны: на пересечениях
/// (3+ направления) с участием крупной дороги ([majorHighwayTypes]) — во
/// дворах их нет. В Южном районе это 21 узел.
class TrafficSignals {
  TrafficSignals._(this.network, this.intersections, this._byNode, this.approaches);

  factory TrafficSignals.fromNetwork(TrafficNetwork network, {double clusterRadius = 25.0}) {
    final graph = network.graph;
    final neighbors = <String, Set<String>>{};
    final majorEdge = <String, RoadGraphEdge>{};
    for (final edge in graph.edges) {
      if (!trafficHighwayTypes.contains(edge.highway)) continue;
      (neighbors[edge.from] ??= {}).add(edge.to);
      (neighbors[edge.to] ??= {}).add(edge.from);
      if (majorHighwayTypes.contains(edge.highway)) {
        majorEdge[edge.from] ??= edge;
        majorEdge[edge.to] ??= edge;
      }
    }

    final candidates = [
      for (final entry in neighbors.entries)
        if (entry.value.length >= 3 && majorEdge.containsKey(entry.key)) entry.key,
    ]..sort();

    // Склейка соседних узлов в один перекрёсток (жадно, по порядку id —
    // детерминированно от запуска к запуску).
    final intersections = <SignalizedIntersection>[];
    final byNode = <String, SignalizedIntersection>{};
    final assigned = <String>{};
    for (final id in candidates) {
      if (assigned.contains(id)) continue;
      final origin = graph.nodes[id]!.toVector3();
      final cluster = {
        for (final other in candidates)
          if (!assigned.contains(other) && (graph.nodes[other]!.toVector3() - origin).length <= clusterRadius) other,
      };
      assigned.addAll(cluster);

      final center = vm.Vector3.zero();
      for (final member in cluster) {
        center.add(graph.nodes[member]!.toVector3());
      }
      center.scale(1.0 / cluster.length);

      final major = majorEdge[id]!;
      final a = graph.nodes[major.from]!;
      final b = graph.nodes[major.to]!;
      final axis = vm.Vector3(b.x - a.x, 0, b.z - a.z)..normalize();

      final intersection = SignalizedIntersection(
        nodeIds: cluster,
        center: center,
        referenceAxis: axis,
        offsetSeconds: _stableFraction(id) * SignalTiming.cycle,
      );
      intersections.add(intersection);
      for (final member in cluster) {
        byNode[member] = intersection;
      }
    }

    final approaches = <SignalApproach>[];
    for (final entry in network.adjacency.entries) {
      for (final toId in entry.value) {
        final intersection = byNode[toId];
        if (intersection == null || intersection.nodeIds.contains(entry.key)) continue;
        final from = graph.nodes[entry.key]!;
        final to = graph.nodes[toId]!;
        final direction = vm.Vector3(to.x - from.x, 0, to.z - from.z);
        if (direction.length2 < 1e-6) continue;
        approaches.add(SignalApproach(
          intersection: intersection,
          fromNodeId: entry.key,
          toNodeId: toId,
          direction: direction.normalized(),
        ));
      }
    }
    return TrafficSignals._(network, intersections, byNode, approaches);
  }

  final TrafficNetwork network;
  final List<SignalizedIntersection> intersections;
  final Map<String, SignalizedIntersection> _byNode;
  final List<SignalApproach> approaches;

  /// Время цикла, секунды — одно на весь город.
  double time = 0.0;

  void advance(double dt) => time += dt;

  /// Сигнал для машины, едущей по ребру [from] -> [to], или null, если на
  /// [to] светофора нет либо машина уже внутри перекрёстка (оба узла —
  /// части одного двойного перекрёстка).
  SignalLight? lightForEdge(String from, String to) {
    final intersection = _byNode[to];
    if (intersection == null || intersection.nodeIds.contains(from)) return null;
    final a = network.graph.nodes[from];
    final b = network.graph.nodes[to];
    if (a == null || b == null) return null;
    final direction = vm.Vector3(b.x - a.x, 0, b.z - a.z);
    if (direction.length2 < 1e-6) return null;
    return intersection.lightFor(direction.normalized(), time);
  }

  /// Перекрёсток, в зону которого (радиус [radius] от центра) попадает
  /// [position], — для проверки проезда игрока на красный.
  SignalizedIntersection? intersectionAt(vm.Vector3 position, {double radius = 8.0}) {
    for (final intersection in intersections) {
      final dx = intersection.center.x - position.x;
      final dz = intersection.center.z - position.z;
      if (dx * dx + dz * dz <= radius * radius) return intersection;
    }
    return null;
  }
}

/// Крупные дороги — светофор ставится там, где пересекается хотя бы одна
/// из них. В районе крупнее `tertiary` ничего нет, но граф может вырасти.
const Set<String> majorHighwayTypes = {'tertiary', 'secondary', 'primary'};

/// Детерминированное "случайное" число 0..1 от id узла — String.hashCode
/// не гарантирует одно и то же значение между запусками.
double _stableFraction(String id) {
  var hash = 17;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return (hash % 1000) / 1000.0;
}

/// Ловит проезд игрока на красный: срабатывает один раз, когда машина
/// въезжает в зону перекрёстка на скорости, а для её направления горит
/// красный. Отдельный объект с состоянием "в какой зоне был в прошлом
/// кадре", чтобы не начислять звезду каждый кадр внутри перекрёстка.
class RedLightDetector {
  RedLightDetector(this.signals, {this.minSpeed = 3.0});

  final TrafficSignals signals;

  /// Медленнее — это не проезд, а, скорее, выезд со двора или толкучка.
  final double minSpeed;

  SignalizedIntersection? _inside;

  /// true ровно в кадр въезда в перекрёсток на красный.
  bool update(vm.Vector3 position, vm.Vector2 velocityXZ) {
    final current = signals.intersectionAt(position);
    final entered = current != null && !identical(current, _inside);
    _inside = current;
    if (!entered) return false;
    final speed = velocityXZ.length;
    if (speed < minSpeed) return false;
    final direction = vm.Vector3(velocityXZ.x / speed, 0, velocityXZ.y / speed);
    return current.lightFor(direction, signals.time) == SignalLight.red;
  }
}
