#!/usr/bin/env bash
# Конвертирует yuzhny_raw.osm (см. fetch_osm_data.sh) в glTF-модель квартала
# и кладёт её в assets/models/world/ — оттуда игра грузит её через loadScene.
#
# Использование: ./convert_to_glb.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_FILE="$SCRIPT_DIR/yuzhny_raw.osm"
OUT_DIR="$SCRIPT_DIR/../../assets/models/world"
OUT_FILE="$OUT_DIR/yuzhny_district.glb"
JAR="$SCRIPT_DIR/osm2world_bin/OSM2World.jar"

if [ ! -f "$INPUT_FILE" ]; then
  echo "Нет $INPUT_FILE — сначала запусти ./fetch_osm_data.sh" >&2
  exit 1
fi
if [ ! -f "$JAR" ]; then
  echo "osm2world не установлен — сначала запусти ./setup_osm2world.sh" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

java -jar "$JAR" convert -i "$INPUT_FILE" -o "$OUT_FILE" --lod 2

echo "Готово: $OUT_FILE ($(du -h "$OUT_FILE" | cut -f1))"
