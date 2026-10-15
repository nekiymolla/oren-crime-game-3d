#!/usr/bin/env bash
# Скачивает бесплатный (CC0) пак с itch.io без браузера: тот же запрос, что
# делает кнопка Download на странице пака с ценой 0.
# Использование: fetch_itch.sh <url страницы пака> <папка для zip>
# Архивы кладём в build/ (в git не попадают) — в репозиторий идут только
# отобранные и пережатые модели.
set -euo pipefail
page="$1"
out="$2"
mkdir -p "$out"
jar="$(mktemp)"
trap 'rm -f "$jar"' EXIT

html="$(curl -sL -c "$jar" -b "$jar" "$page")"
csrf="$(printf '%s' "$html" | grep -oE 'name="csrf_token" value="[^"]+"' | head -1 | sed -E 's/.*value="//; s/"$//')"
# Список файлов — со страницы загрузок.
dl="$(curl -s -c "$jar" -b "$jar" -X POST "$page/download_url" --data-urlencode "csrf_token=$csrf" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["url"])')"
ids="$(curl -sL -c "$jar" -b "$jar" "$dl" | grep -oE 'upload_id="[0-9]+"' | grep -oE '[0-9]+' | sort -u)"

for id in $ids; do
  file_url="$(curl -s -c "$jar" -b "$jar" -X POST "$page/file/$id?source=view_game&as_props=1&after_download_lightbox=true" \
    --data-urlencode "csrf_token=$csrf" | python3 -c 'import json,sys; print(json.load(sys.stdin)["url"])')"
  echo "upload $id -> $out"
  (cd "$out" && curl -sL -OJ "$file_url")
done
