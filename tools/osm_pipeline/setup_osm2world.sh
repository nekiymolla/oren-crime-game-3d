#!/usr/bin/env bash
# Скачивает и распаковывает osm2world (build-time инструмент, ~450 МБ) в
# osm2world_bin/ рядом со скриптом. Не коммитится в git (см. .gitignore) —
# запускается заново на любой машине, где нужно (пере)генерировать геометрию.
#
# Использование: ./setup_osm2world.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$SCRIPT_DIR/osm2world_bin"
ZIP_FILE="$SCRIPT_DIR/osm2world.zip"

if [ -f "$BIN_DIR/OSM2World.jar" ]; then
  echo "osm2world уже установлен в $BIN_DIR"
  exit 0
fi

echo "Скачиваю OSM2World (~450 МБ, один раз)..."
curl -sSL https://osm2world.org/download/files/latest/OSM2World-latest-bin.zip -o "$ZIP_FILE"

mkdir -p "$BIN_DIR"
unzip -q "$ZIP_FILE" -d "$BIN_DIR"
rm "$ZIP_FILE"

echo "Готово: $BIN_DIR/OSM2World.jar"
