import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as vm;

/// Дорожный граф из OSM (`highway=*`), сгенерированный
/// `tools/osm_pipeline/build_road_graph.py` — узлы (перекрёстки и точки
/// изгиба дороги) и рёбра между ними в той же локальной системе координат,
/// что и геометрия района (см. recenter.mjs). Основа для будущих
/// NPC-пешеходов/трафика/полиции (см. PROGRESS.md) — сама визуальная
/// геометрия района не хранит топологию дорог, только меши.
class RoadGraphNode {
  const RoadGraphNode({required this.id, required this.x, required this.z});

  factory RoadGraphNode.fromJson(Map<String, dynamic> json) => RoadGraphNode(
    id: json['id'] as String,
    x: (json['x'] as num).toDouble(),
    z: (json['z'] as num).toDouble(),
  );

  final String id;
  final double x;
  final double z;

  vm.Vector3 toVector3({double y = 0}) => vm.Vector3(x, y, z);
}

class RoadGraphEdge {
  const RoadGraphEdge({
    required this.from,
    required this.to,
    required this.highway,
    required this.oneway,
  });

  factory RoadGraphEdge.fromJson(Map<String, dynamic> json) => RoadGraphEdge(
    from: json['from'] as String,
    to: json['to'] as String,
    highway: json['highway'] as String,
    oneway: json['oneway'] as bool,
  );

  final String from;
  final String to;

  /// Значение тега OSM `highway` (residential, footway, path, ...).
  final String highway;
  final bool oneway;
}

class RoadGraph {
  const RoadGraph({required this.nodes, required this.edges});

  factory RoadGraph.fromJson(Map<String, dynamic> json) {
    final nodes = {
      for (final raw in json['nodes'] as List)
        (raw as Map<String, dynamic>)['id'] as String: RoadGraphNode.fromJson(raw),
    };
    final edges = [
      for (final raw in json['edges'] as List) RoadGraphEdge.fromJson(raw as Map<String, dynamic>),
    ];
    return RoadGraph(nodes: nodes, edges: edges);
  }

  /// Узлы по id — используется рёбрами и любым будущим потребителем
  /// (пешеходы/трафик будут искать ближайший узел к точке на карте).
  final Map<String, RoadGraphNode> nodes;
  final List<RoadGraphEdge> edges;
}

Future<RoadGraph> loadRoadGraph() async {
  final raw = await rootBundle.loadString('assets/data/road_graph.json');
  return RoadGraph.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

/// Временная отладочная визуализация — тонкие цветные линии вдоль дорог,
/// приподнятые над землёй на [heightOffset], чтобы не сливаться с дорожным
/// полотном (z-fighting). Полноценного потребителя графа (NPC/трафик) пока
/// нет, а без визуализации саму топологию было бы не проверить на устройстве
/// без ручного дебага (см. PROGRESS.md).
Node buildRoadGraphDebugNode(RoadGraph graph, {double heightOffset = 0.15}) {
  final positions = Float32List(graph.edges.length * 6);
  var i = 0;
  for (final edge in graph.edges) {
    final from = graph.nodes[edge.from];
    final to = graph.nodes[edge.to];
    if (from == null || to == null) continue;
    positions[i++] = from.x;
    positions[i++] = heightOffset;
    positions[i++] = from.z;
    positions[i++] = to.x;
    positions[i++] = heightOffset;
    positions[i++] = to.z;
  }

  final geometry = LineSegmentsGeometry(
    LineSegmentData(positions: positions.sublist(0, i)),
    width: 0.3,
  );
  final material = UnlitMaterial()..baseColorFactor = vm.Vector4(1.0, 0.85, 0.1, 1.0);
  return Node(mesh: Mesh(geometry, material));
}
