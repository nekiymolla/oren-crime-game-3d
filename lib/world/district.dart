import 'package:flutter_scene/scene.dart';

/// Квартал Южного района Оренбурга вокруг дома игрока (ул. Весенняя, 3),
/// сгенерированный из OpenStreetMap через osm2world.
/// См. tools/osm_pipeline/ для пайплайна пересборки.
const String yuzhnyDistrictAsset = 'assets/models/world/yuzhny_district.glb';

Future<Node> loadYuzhnyDistrict() => loadScene(yuzhnyDistrictAsset);
