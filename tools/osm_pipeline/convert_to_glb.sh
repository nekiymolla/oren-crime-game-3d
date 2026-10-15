#!/usr/bin/env bash
# Конвертирует yuzhny_raw.osm (см. fetch_osm_data.sh) в glTF-модель квартала
# и кладёт её в assets/models/world/ — оттуда игра грузит её через loadScene.
#
# Использование: ./convert_to_glb.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_FILE="$SCRIPT_DIR/yuzhny_raw.osm"
OUT_DIR="$SCRIPT_DIR/../../assets/models/world"
CHUNKS_DIR="$OUT_DIR/chunks"
RAW_FILE="$OUT_DIR/yuzhny_district_raw.glb"
RECENTERED_FILE="$OUT_DIR/yuzhny_district_recentered.glb"
JAR="$SCRIPT_DIR/osm2world_bin/OSM2World.jar"
CALIBRATION_FILE="$SCRIPT_DIR/calibration.json"
# Должен совпадать по смыслу с chunkSizeMeters в assets/data/world.json.
CELL_SIZE_METERS=200
# Совпадает с geoOrigin в assets/data/world.json и fetch_osm_data.sh.
GEO_ORIGIN_LAT=51.715510
GEO_ORIGIN_LON=55.107186

if [ ! -f "$INPUT_FILE" ]; then
  echo "Нет $INPUT_FILE — сначала запусти ./fetch_osm_data.sh" >&2
  exit 1
fi
if [ ! -f "$JAR" ]; then
  echo "osm2world не установлен — сначала запусти ./setup_osm2world.sh" >&2
  exit 1
fi
if [ ! -d "$SCRIPT_DIR/node_modules/@gltf-transform" ]; then
  echo "Зависимости для нарезки на чанки не установлены — сначала: cd $SCRIPT_DIR && npm install" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

# --config обязателен: без него osm2world не находит рядом лежащий
# standard.properties (тот ищется относительно РАБОЧЕЙ ДИРЕКТОРИИ процесса,
# как в официальном osm2world.sh, который перед запуском делает `cd` в свою
# папку — мы конфиг просто передаём явно, не завися от cwd вызывающего).
# Без этого молча включается голый fallback-стиль: 0 текстур, случайные
# материалы вроде "GARAGE_DOOR"/"MARBLE" (см. PROGRESS.md).
java -jar "$JAR" convert -i "$INPUT_FILE" -o "$RAW_FILE" --lod 2 \
  --config "$SCRIPT_DIR/osm2world_bin/standard.properties"

# osm2world сам выбирает локальный (0,0,0) по разбросу узлов файла — сдвигает
# его обратно так, чтобы geoOrigin (маячки из add_anchor_node.py) оказался
# ровно в (0,0), иначе спавн игрока не совпадает с домом (см. PROGRESS.md).
# Заодно пишет calibration.json — по нему build_road_graph.mjs проецирует
# дорожный граф в ту же систему координат, не гоняя его через osm2world.
node "$SCRIPT_DIR/recenter.mjs" "$RAW_FILE" "$RECENTERED_FILE" "$CALIBRATION_FILE" \
  "$GEO_ORIGIN_LAT" "$GEO_ORIGIN_LON"
rm "$RAW_FILE"

# Реальная площадь района — под два километра в поперечнике, поэтому сырой
# .glb разбивается на пространственные ячейки (grid_split.mjs) и грузится
# в игре только рядом с игроком (см. lib/world/district_streamer.dart) —
# иначе рендер и raycast-коллизии считаются по всей геометрии сразу.
rm -rf "$CHUNKS_DIR"
node "$SCRIPT_DIR/grid_split.mjs" "$RECENTERED_FILE" "$CHUNKS_DIR" "$CELL_SIZE_METERS"
# Окна домов светятся ночью, дороги мокнут в дождь — помечаем их материалы (см. скрипт).
node "$SCRIPT_DIR/mark_night_materials.mjs" "$CHUNKS_DIR"
# Карта района для радара/компаса HUD — вид сверху по той же геометрии.
node "$SCRIPT_DIR/render_minimap.mjs" "$CHUNKS_DIR" \
  "$SCRIPT_DIR/../../assets/data/minimap.png" "$SCRIPT_DIR/../../assets/data/minimap.json"
rm "$RECENTERED_FILE"

# Дорожный граф (highway=* из сырого .osm) для будущих NPC/трафика/полиции
# (см. PROGRESS.md) — координаты через ту же калибровку, что и геометрия.
python3 "$SCRIPT_DIR/build_road_graph.py" "$INPUT_FILE" "$CALIBRATION_FILE" \
  "$SCRIPT_DIR/../../assets/data/road_graph.json"

# Пешеходы и трафик двигаются по рёбрам графа по прямой — ни одно не
# должно проходить сквозь здания в 3D-геометрии (баг "пешеходы сквозь
# стены", см. BUGS.md).
node "$SCRIPT_DIR/check_road_graph.mjs" "$CHUNKS_DIR" \
  "$SCRIPT_DIR/../../assets/data/road_graph.json"

# Неоновые вывески: кандидаты — стены домов вдоль крупных улиц (OSM),
# отбор — по 3D-геометрии чанков (см. оба скрипта).
python3 "$SCRIPT_DIR/place_neon_signs.py" "$INPUT_FILE" "$CALIBRATION_FILE" \
  "$SCRIPT_DIR/../../assets/data/road_graph.json" "$SCRIPT_DIR/neon_candidates.json"
node "$SCRIPT_DIR/filter_neon_signs.mjs" "$CHUNKS_DIR" "$SCRIPT_DIR/neon_candidates.json" \
  "$SCRIPT_DIR/../../assets/data/neon_signs.json"

echo "Готово: $CHUNKS_DIR ($(du -sh "$CHUNKS_DIR" | cut -f1))"
