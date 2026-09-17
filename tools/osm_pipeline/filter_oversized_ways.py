#!/usr/bin/env python3
"""Убирает way'и, чьи узлы расползаются далеко за пределы bbox запроса.

Overpass возвращает ЦЕЛИКОМ любой way, у которого хотя бы один узел попал в
bbox (плюс все его узлы через ">;") — гигантский полигон landuse=residential
(административная зона на весь город), едва задевающий наш bbox краем,
утягивает за собой узлы за много километров от дома игрока. osm2world
берёт систему координат из общего bounding box всех узлов файла, так что
такой один way сдвигает (0,0,0) игры прочь от geoOrigin — тихо и незаметно,
пока не сравнишь координаты чанков после конвертации.

Вызывается из fetch_osm_data.sh сразу после скачивания, до osm2world.
Затрагивает только <way> (не <relation> — оверсайз-relation пока не
встречался, см. PROGRESS.md, если появится — фильтровать надо будет и их).
"""

import sys
import xml.etree.ElementTree as ET

USAGE = "Использование: filter_oversized_ways.py <file.osm> <south> <west> <north> <east> <toleranceFactor>"


def main() -> int:
    if len(sys.argv) != 7:
        print(USAGE, file=sys.stderr)
        return 1

    path, south, west, north, east, tolerance = sys.argv[1:]
    south, west, north, east, tolerance = map(float, (south, west, north, east, tolerance))
    lat_span = north - south
    lon_span = east - west
    max_lat_span = lat_span * tolerance
    max_lon_span = lon_span * tolerance

    tree = ET.parse(path)
    root = tree.getroot()

    nodes = {
        n.get("id"): (float(n.get("lat")), float(n.get("lon")))
        for n in root.findall("node")
    }

    removed = []
    for way in list(root.findall("way")):
        refs = [nd.get("ref") for nd in way.findall("nd")]
        coords = [nodes[r] for r in refs if r in nodes]
        if not coords:
            continue
        lats = [c[0] for c in coords]
        lons = [c[1] for c in coords]
        if (max(lats) - min(lats)) > max_lat_span or (max(lons) - min(lons)) > max_lon_span:
            tags = {t.get("k"): t.get("v") for t in way.findall("tag")}
            removed.append((way.get("id"), tags))
            root.remove(way)

    if removed:
        print(f"Убрано way'ев (расползлись за пределы bbox x{tolerance}): {len(removed)}")
        for way_id, tags in removed:
            print(f"  way {way_id}: {tags}")
    else:
        print("Ни один way не превысил допустимый размер — фильтр ничего не убрал.")

    tree.write(path, encoding="UTF-8", xml_declaration=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
