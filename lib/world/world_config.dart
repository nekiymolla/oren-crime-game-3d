import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:vector_math/vector_math.dart' as vm;

/// Общие параметры мира из assets/data/world.json (не зашиты в код, чтобы
/// геодизайнер мог править без пересборки Dart-кода).
class WorldConfig {
  const WorldConfig({
    required this.chunkSizeMeters,
    required this.streamingRadiusChunks,
    required this.playerSpawnPosition,
    required this.playerSpawnHeadingDegrees,
  });

  factory WorldConfig.fromJson(Map<String, dynamic> json) {
    final spawn = json['playerSpawn'] as Map<String, dynamic>;
    final pos = (spawn['positionLocal'] as List).cast<num>();
    return WorldConfig(
      chunkSizeMeters: (json['chunkSizeMeters'] as num).toDouble(),
      streamingRadiusChunks: json['streamingRadiusChunks'] as int,
      playerSpawnPosition: vm.Vector3(pos[0].toDouble(), pos[1].toDouble(), pos[2].toDouble()),
      playerSpawnHeadingDegrees: (spawn['headingDegrees'] as num).toDouble(),
    );
  }

  /// Размер стороны одной ячейки грида района, метры. Должен совпадать с
  /// cellSizeMeters, с которым запускался tools/osm_pipeline/grid_split.mjs
  /// (см. DistrictManifest.cellSizeMeters — она читается из самого
  /// манифеста чанков, а не отсюда, так что рассинхрон не сломает загрузку,
  /// только может не совпасть по смыслу с этим числом).
  final double chunkSizeMeters;

  /// Сколько ячеек вокруг игрока держать загруженными по каждой оси
  /// (радиус 1 = 3x3 = 9 ячеек, радиус 2 = 5x5 и т.д.).
  final int streamingRadiusChunks;

  /// Точка спавна игрока — НЕ (0,0,0)/geoOrigin буквально: адресная точка
  /// дома геокодируется в его геометрический центр, а не во двор перед ним
  /// (см. PROGRESS.md, баг "заспавнился внутри дома"). (0,0,0) — ещё и угол
  /// сразу 4 чанков сетки: там же мельтешащая от столкновения со стенами
  /// позиция дёргала DistrictStreamer каждый кадр — тоже причина фризов.
  final vm.Vector3 playerSpawnPosition;
  final double playerSpawnHeadingDegrees;
}

Future<WorldConfig> loadWorldConfig() async {
  final raw = await rootBundle.loadString('assets/data/world.json');
  return WorldConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
