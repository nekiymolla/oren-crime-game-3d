#!/usr/bin/env bash
# Скачивает дороги, здания, зоны (landuse/leisure — газоны, парки, скверы),
# природные объекты (natural — вода, лес и т.п.) и отдельно стоящие деревья
# (natural=tree — в OSM это одиночные <node>, а не way, поэтому запрашиваются
# отдельно) OpenStreetMap для тестового квартала Южного района Оренбурга
# (~1x1 км вокруг дома игрока, ул. Весенняя, 3) через Overpass API. Без
# этого между зданиями видна плейсхолдер-земля (osm2world строит
# поверхности только там, где есть разметка). Результат — yuzhny_raw.osm
# рядом со скриптом, вход для osm2world.
#
# Использование: ./fetch_osm_data.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_FILE="$SCRIPT_DIR/yuzhny_raw.osm"
QUERY_FILE="$SCRIPT_DIR/overpass_query.txt"

# Совпадает с geoOrigin в assets/data/world.json.
GEO_ORIGIN_LAT=51.715510
GEO_ORIGIN_LON=55.107186

# Bbox: ±0.5 км от дома игрока, ул. Весенняя, 3.
SOUTH=51.71102
WEST=55.09994
NORTH=51.72000
EAST=55.11444

cat > "$QUERY_FILE" <<EOF
[out:xml][timeout:60];
(
  way["highway"](${SOUTH},${WEST},${NORTH},${EAST});
  way["building"](${SOUTH},${WEST},${NORTH},${EAST});
  relation["building"](${SOUTH},${WEST},${NORTH},${EAST});
  way["landuse"](${SOUTH},${WEST},${NORTH},${EAST});
  relation["landuse"](${SOUTH},${WEST},${NORTH},${EAST});
  way["natural"](${SOUTH},${WEST},${NORTH},${EAST});
  relation["natural"](${SOUTH},${WEST},${NORTH},${EAST});
  way["leisure"](${SOUTH},${WEST},${NORTH},${EAST});
  relation["leisure"](${SOUTH},${WEST},${NORTH},${EAST});
  node["natural"="tree"](${SOUTH},${WEST},${NORTH},${EAST});
);
out body;
>;
out skel qt;
EOF

echo "Запрашиваю Overpass API (bbox ${SOUTH},${WEST},${NORTH},${EAST})..."

# overpass-api.de иногда перегружен (504) — есть зеркало kumi.systems.
fetch() {
  curl -sS --fail --data-urlencode "data@${QUERY_FILE}" \
    -H "User-Agent: crime-oren-dev/0.1 (osm2world pipeline)" \
    "$1" -o "$OUT_FILE" -w "HTTP:%{http_code}\n"
}

fetch "https://overpass.kumi.systems/api/interpreter" \
  || fetch "https://overpass-api.de/api/interpreter"

# Overpass тянет way целиком, если хоть один узел попал в bbox — гигантский
# landuse-полигон (админ-зона на весь город), едва задевающий край, утащит
# за собой узлы за километры и сдвинет систему координат osm2world прочь от
# geoOrigin (см. PROGRESS.md). x3 от размера bbox — с запасом на реальные
# крупные объекты (парк, пруд), но не на зоны в масштабе всего города.
python3 "$SCRIPT_DIR/filter_oversized_ways.py" "$OUT_FILE" "$SOUTH" "$WEST" "$NORTH" "$EAST" 3

# Маячок для recenter.mjs (см. convert_to_glb.sh) — компенсирует то, что
# osm2world сам выбирает локальный (0,0,0) по разбросу узлов файла, а не по
# geoOrigin явно; без маячка даже отфильтрованная выше асимметрия соседних
# улиц/полигонов может незаметно сдвинуть спавн игрока от дома.
python3 "$SCRIPT_DIR/add_anchor_node.py" "$OUT_FILE" "$GEO_ORIGIN_LAT" "$GEO_ORIGIN_LON"

echo "Готово: $OUT_FILE ($(du -h "$OUT_FILE" | cut -f1))"
