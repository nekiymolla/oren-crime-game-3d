#!/usr/bin/env bash
# Скачивает дороги и здания OpenStreetMap для тестового квартала Южного
# района Оренбурга (~1x1 км вокруг дома игрока, ул. Весенняя, 3) через
# Overpass API. Результат — yuzhny_raw.osm рядом со скриптом, вход для osm2world.
#
# Использование: ./fetch_osm_data.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_FILE="$SCRIPT_DIR/yuzhny_raw.osm"
QUERY_FILE="$SCRIPT_DIR/overpass_query.txt"

# Bbox: ±0.5 км от дома игрока (51.715510, 55.107186), ул. Весенняя, 3.
# Совпадает с geoOrigin в assets/data/world.json.
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

echo "Готово: $OUT_FILE ($(du -h "$OUT_FILE" | cut -f1))"
