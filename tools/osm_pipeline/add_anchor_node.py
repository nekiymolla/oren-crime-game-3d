#!/usr/bin/env python3
"""Добавляет в .osm-файл искусственное маленькое "здание"-маячок ровно в
geoOrigin с уникальной высотой (см. ANCHOR_HEIGHT) — по ней recenter.mjs
находит маячок в сконвертированном glTF и вычисляет, куда osm2world
поместил geoOrigin в своей локальной системе координат, чтобы сдвинуть всю
геометрию обратно к (0,0) (см. filter_oversized_ways.py — без этого узлы
за пределами bbox незаметно смещают origin osm2world).

Вызывается из fetch_osm_data.sh после filter_oversized_ways.py.
"""

import sys
import xml.etree.ElementTree as ET

USAGE = "Использование: add_anchor_node.py <file.osm> <lat> <lon>"

# Огромная, невозможная в реальных данных высота — чтобы однозначно найти
# маячок среди обычных зданий (recenter.mjs ищет вершину с Y ~= это число).
ANCHOR_HEIGHT = 12345
# Полуразмер маячка-квадрата в градусах (~0.5 м) — не должен пересекать
# соседние реальные здания.
HALF_SIZE_DEG = 0.000005


def main() -> int:
    if len(sys.argv) != 4:
        print(USAGE, file=sys.stderr)
        return 1

    path, lat_s, lon_s = sys.argv[1:]
    lat, lon = float(lat_s), float(lon_s)

    tree = ET.parse(path)
    root = tree.getroot()

    corners = [
        (lat - HALF_SIZE_DEG, lon - HALF_SIZE_DEG),
        (lat - HALF_SIZE_DEG, lon + HALF_SIZE_DEG),
        (lat + HALF_SIZE_DEG, lon + HALF_SIZE_DEG),
        (lat + HALF_SIZE_DEG, lon - HALF_SIZE_DEG),
    ]

    node_ids = []
    for i, (nlat, nlon) in enumerate(corners):
        node_id = str(-1000 - i)
        node = ET.SubElement(root, "node")
        node.set("id", node_id)
        node.set("lat", f"{nlat:.9f}")
        node.set("lon", f"{nlon:.9f}")
        node.set("visible", "true")
        node_ids.append(node_id)
    node_ids.append(node_ids[0])  # замкнуть way

    way = ET.SubElement(root, "way")
    way.set("id", "-2000")
    way.set("visible", "true")
    for node_id in node_ids:
        nd = ET.SubElement(way, "nd")
        nd.set("ref", node_id)
    for k, v in {
        "building": "yes",
        "height": str(ANCHOR_HEIGHT),
        "crime_oren:anchor": "geo_origin",
    }.items():
        tag = ET.SubElement(way, "tag")
        tag.set("k", k)
        tag.set("v", v)

    tree.write(path, encoding="UTF-8", xml_declaration=True)
    print(f"Маячок-якорь добавлен в ({lat}, {lon}), height={ANCHOR_HEIGHT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
