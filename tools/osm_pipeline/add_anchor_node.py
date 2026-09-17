#!/usr/bin/env python3
"""Добавляет в .osm-файл три искусственных маленьких "здания"-маячка с
уникальными высотами (см. ANCHORS) — по ним recenter.mjs эмпирически
калибрует полную афинную проекцию lat/lon -> локальные координаты игры:
не только сдвиг (куда osm2world помещает geoOrigin), но и фактические
направления/масштаб осей X/Z, ничего не предполагая про формулу проекции
внутри osm2world.

- origin: ровно в geoOrigin — даёт сдвиг (см. recenter.mjs).
- north:  geoOrigin + ANCHOR_OFFSET_METERS строго на север — даёт вектор
          "север" в локальных координатах.
- east:   geoOrigin + ANCHOR_OFFSET_METERS строго на восток — даёт вектор
          "восток" в локальных координатах.

Используется build_road_graph.mjs, чтобы спроецировать узлы дорожного
графа (lat/lon из сырого .osm) в ту же систему координат, что и сама
геометрия района, без повторного прогона через osm2world.

Вызывается из fetch_osm_data.sh после filter_oversized_ways.py.
"""

import math
import sys
import xml.etree.ElementTree as ET

USAGE = "Использование: add_anchor_node.py <file.osm> <lat> <lon>"

ANCHOR_OFFSET_METERS = 200.0
METERS_PER_DEGREE_LAT = 111_320.0

# Огромные, невозможные в реальных данных высоты — чтобы однозначно найти
# каждый маячок среди обычных зданий (recenter.mjs ищет вершины с Y ~= это
# число). ИДы (name) должны совпадать с тем, что читает recenter.mjs.
ANCHORS = {
    "origin": 12345,
    "north": 23456,
    "east": 34567,
}
# Полуразмер маячка-квадрата в градусах (~0.5 м) — не должен пересекать
# соседние реальные здания.
HALF_SIZE_DEG = 0.000005


def add_anchor(root: ET.Element, name: str, lat: float, lon: float, height: int, way_id: int) -> None:
    # Узлы нумеруются от way_id*10 вниз — при way_id из {-1,-2,-3} диапазоны
    # узлов (-14..-11, -24..-21, -34..-31) не пересекаются между маячками.
    node_base = way_id * 10
    corners = [
        (lat - HALF_SIZE_DEG, lon - HALF_SIZE_DEG),
        (lat - HALF_SIZE_DEG, lon + HALF_SIZE_DEG),
        (lat + HALF_SIZE_DEG, lon + HALF_SIZE_DEG),
        (lat + HALF_SIZE_DEG, lon - HALF_SIZE_DEG),
    ]
    node_ids = []
    for i, (nlat, nlon) in enumerate(corners):
        node_id = str(node_base - i)
        node = ET.SubElement(root, "node")
        node.set("id", node_id)
        node.set("lat", f"{nlat:.9f}")
        node.set("lon", f"{nlon:.9f}")
        node.set("visible", "true")
        node_ids.append(node_id)
    node_ids.append(node_ids[0])  # замкнуть way

    way = ET.SubElement(root, "way")
    way.set("id", str(way_id))
    way.set("visible", "true")
    for node_id in node_ids:
        nd = ET.SubElement(way, "nd")
        nd.set("ref", node_id)
    for k, v in {
        "building": "yes",
        "height": str(height),
        "crime_oren:anchor": name,
    }.items():
        tag = ET.SubElement(way, "tag")
        tag.set("k", k)
        tag.set("v", v)
    print(f"Маячок-якорь '{name}' добавлен в ({lat:.7f}, {lon:.7f}), height={height}")


def main() -> int:
    if len(sys.argv) != 4:
        print(USAGE, file=sys.stderr)
        return 1

    path, lat_s, lon_s = sys.argv[1:]
    lat, lon = float(lat_s), float(lon_s)

    meters_per_degree_lon = METERS_PER_DEGREE_LAT * math.cos(math.radians(lat))
    lat_delta = ANCHOR_OFFSET_METERS / METERS_PER_DEGREE_LAT
    lon_delta = ANCHOR_OFFSET_METERS / meters_per_degree_lon

    tree = ET.parse(path)
    root = tree.getroot()

    add_anchor(root, "origin", lat, lon, ANCHORS["origin"], -1)
    add_anchor(root, "north", lat + lat_delta, lon, ANCHORS["north"], -2)
    add_anchor(root, "east", lat, lon + lon_delta, ANCHORS["east"], -3)

    tree.write(path, encoding="UTF-8", xml_declaration=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
