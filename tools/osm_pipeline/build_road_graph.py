#!/usr/bin/env python3
"""Строит дорожный граф из way["highway"] в сыром .osm — узлы (перекрёстки
и точки изгиба дороги) с координатами в ТОЙ ЖЕ локальной системе, что и
геометрия района, плюс рёбра между последовательными узлами каждой дороги.

Нужен для будущих NPC-пешеходов/трафика/полиции (см. PROGRESS.md) — сама
геометрия района не хранит топологию OSM-дорог, только визуальные меши.

Координаты проецируются через calibration.json (см. recenter.mjs) —
эмпирическую афинную калибровку lat/lon -> локальные координаты, а не
предположение о формуле проекции внутри osm2world.

Вызывается из convert_to_glb.sh после recenter.mjs (calibration.json должен
уже существовать).

Использование: build_road_graph.py <file.osm> <calibration.json> <out.json>
"""

import json
import sys
import xml.etree.ElementTree as ET

USAGE = "Использование: build_road_graph.py <file.osm> <calibration.json> <out.json>"


def project(calibration: dict, lat: float, lon: float) -> tuple[float, float]:
    meters_north = (lat - calibration["originLat"]) * calibration["metersPerDegreeLat"]
    meters_east = (lon - calibration["originLon"]) * calibration["metersPerDegreeLon"]
    east_unit = calibration["eastUnit"]
    north_unit = calibration["northUnit"]
    x = meters_east * east_unit["x"] + meters_north * north_unit["x"]
    z = meters_east * east_unit["z"] + meters_north * north_unit["z"]
    return x, z


def main() -> int:
    if len(sys.argv) != 4:
        print(USAGE, file=sys.stderr)
        return 1

    osm_path, calibration_path, out_path = sys.argv[1:]

    with open(calibration_path, encoding="utf-8") as f:
        calibration = json.load(f)

    tree = ET.parse(osm_path)
    root = tree.getroot()

    node_coords = {
        n.get("id"): (float(n.get("lat")), float(n.get("lon")))
        for n in root.findall("node")
    }

    used_node_ids = set()
    edges = []
    for way in root.findall("way"):
        tags = {t.get("k"): t.get("v") for t in way.findall("tag")}
        highway = tags.get("highway")
        if not highway:
            continue
        refs = [nd.get("ref") for nd in way.findall("nd")]
        refs = [r for r in refs if r in node_coords]
        if len(refs) < 2:
            continue
        used_node_ids.update(refs)
        oneway = tags.get("oneway") in ("yes", "true", "1")
        for a, b in zip(refs, refs[1:]):
            edges.append({"from": a, "to": b, "highway": highway, "oneway": oneway})

    nodes = []
    for node_id in used_node_ids:
        lat, lon = node_coords[node_id]
        x, z = project(calibration, lat, lon)
        nodes.append({"id": node_id, "x": round(x, 2), "z": round(z, 2)})

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"nodes": nodes, "edges": edges}, f, ensure_ascii=False, indent=2)

    print(f"Дорожный граф: {len(nodes)} узлов, {len(edges)} рёбер -> {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
