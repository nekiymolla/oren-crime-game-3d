import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart';
import 'streaming_diagnostics.dart';

/// Каталог чанков квартала Южного района Оренбурга, сгенерированный из
/// OpenStreetMap через osm2world (см. tools/osm_pipeline/).
///
/// Весь квартал разом — это ~1900x1600 метров реальной геометрии (сотни
/// зданий), и держать его в сцене целиком убивает FPS даже там, где игрок
/// физически не может его видеть: и рендер (fill-rate по текстурам зданий
/// за километр от камеры), и коллизии (raycastNode обходит все узлы сцены
/// на каждый луч) стоят пропорционально ОБЩЕМУ размеру геометрии в сцене,
/// а не видимой её части. Поэтому район разбит на квадратные ячейки
/// (grid_split.mjs, cellSizeMeters) и грузится только рядом с игроком —
/// см. DistrictStreamer в lib/world/district_streamer.dart.
const String districtChunksDir = 'assets/models/world/chunks';

/// Одна ячейка сетки — набор зданий/дорог в квадрате cellSizeMeters x
/// cellSizeMeters, начиная от (cellX * cellSizeMeters, cellZ * cellSizeMeters).
class DistrictChunk {
  const DistrictChunk({
    required this.id,
    required this.file,
    required this.cellX,
    required this.cellZ,
    required this.centerX,
    required this.centerZ,
  });

  factory DistrictChunk.fromJson(Map<String, dynamic> json) => DistrictChunk(
    id: json['id'] as String,
    file: json['file'] as String,
    cellX: json['cellX'] as int,
    cellZ: json['cellZ'] as int,
    centerX: (json['centerX'] as num).toDouble(),
    centerZ: (json['centerZ'] as num).toDouble(),
  );

  final String id;
  final String file;
  final int cellX;
  final int cellZ;

  /// Центр bounding box'а реальной геометрии внутри ячейки (не геометрический
  /// центр самой ячейки) — используется только для диагностики/лога.
  final double centerX;
  final double centerZ;
}

/// Манифест всех ячеек, лежит рядом с .glb-файлами чанков.
class DistrictManifest {
  const DistrictManifest({required this.cellSizeMeters, required this.cells});

  factory DistrictManifest.fromJson(Map<String, dynamic> json) =>
      DistrictManifest(
        cellSizeMeters: (json['cellSizeMeters'] as num).toDouble(),
        cells: [
          for (final raw in json['cells'] as List)
            DistrictChunk.fromJson(raw as Map<String, dynamic>),
        ],
      );

  final double cellSizeMeters;
  final List<DistrictChunk> cells;

  /// Номер ячейки по мировой координате (та же формула, что в grid_split.mjs).
  int cellIndexOf(double worldCoord) => (worldCoord / cellSizeMeters).floor();
}

Future<DistrictManifest> loadDistrictManifest() async {
  final raw = await rootBundle.loadString('$districtChunksDir/manifest.json');
  return DistrictManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

Future<Node> loadDistrictChunk(DistrictChunk chunk) async {
  final node = await StreamingDiagnostics.async(
    chunk.id,
    'base-import',
    () => loadScene('$districtChunksDir/${chunk.file}'),
  );
  node.name = 'district:${chunk.id}';
  final details = await StreamingDiagnostics.async(
    chunk.id,
    'detail-import',
    () => loadScene('assets/models/world/details/${chunk.file}'),
  );
  // Fine trim is visual dressing. Testing every sill triangle for each
  // camera/body ray made dense chunks dominate the main thread.
  for (final meshNode in details.meshNodes) {
    meshNode.raycastable =
        meshNode.name == 'RoofMetal' || meshNode.name == 'Porches';
  }
  node.add(details);
  final streets = await StreamingDiagnostics.async(
    chunk.id,
    'street-import',
    () => loadScene('assets/models/world/streets/${chunk.file}'),
  );
  for (final meshNode in streets.meshNodes) {
    meshNode.raycastable = const {
      'CitySolid',
      'CityWood',
      'CityMetal',
      'CitySport',
      'CityEquipment',
      'CityRubber',
      'CityRamp',
      'CityCourtSurface',
      'CitySkateSurface',
    }.contains(meshNode.name);
  }
  node.add(streets);
  return node;
}
