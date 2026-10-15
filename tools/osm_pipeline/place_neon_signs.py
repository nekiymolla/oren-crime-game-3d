#!/usr/bin/env python3
"""Кандидаты под неоновые вывески: стены домов, смотрящие на крупные улицы.

В OSM-выгрузке района заведений почти нет (8 объектов на весь район), так
что вывески ставятся правдоподобно, а не по данным: на первые этажи домов
вдоль "красных линий" — улиц tertiary/unclassified, как магазины в реальном
спальном районе. Дальше filter_neon_signs.mjs проверяет каждого кандидата
по настоящей 3D-геометрии чанков и прореживает.

Использование: place_neon_signs.py <file.osm> <calibration.json> <road_graph.json> <out_candidates.json>
"""

import json
import math
import sys
import xml.etree.ElementTree as ET

from build_road_graph import project

# Улицы, вдоль которых бывают магазины (во дворах вывесок нет).
MAIN_STREETS = {"tertiary", "secondary", "primary", "unclassified"}
MIN_WALL = 7.0          # короче — не стена под вывеску
STREET_MIN, STREET_MAX = 6.0, 30.0  # расстояние от стены до оси улицы


def seg_point_distance(px, pz, ax, az, bx, bz):
    dx, dz = bx - ax, bz - az
    length2 = dx * dx + dz * dz
    t = 0.0 if length2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / length2))
    cx, cz = ax + dx * t, az + dz * t
    return math.hypot(px - cx, pz - cz), cx, cz


def main() -> int:
    if len(sys.argv) != 5:
        print(__doc__, file=sys.stderr)
        return 1
    osm_path, calibration_path, graph_path, out_path = sys.argv[1:]
    calibration = json.load(open(calibration_path, encoding="utf-8"))
    graph = json.load(open(graph_path, encoding="utf-8"))
    nodes = {n["id"]: n for n in graph["nodes"]}
    streets = [
        (nodes[e["from"]], nodes[e["to"]])
        for e in graph["edges"]
        if e["highway"] in MAIN_STREETS and e["from"] in nodes and e["to"] in nodes
    ]

    root = ET.parse(osm_path).getroot()
    coords = {n.get("id"): (float(n.get("lat")), float(n.get("lon"))) for n in root.findall("node")}

    candidates = []
    for way in root.findall("way"):
        tags = {t.get("k"): t.get("v") for t in way.findall("tag")}
        if "building" not in tags:
            continue
        refs = [r.get("ref") for r in way.findall("nd") if r.get("ref") in coords]
        if len(refs) < 4 or refs[0] != refs[-1]:
            continue
        pts = [project(calibration, *coords[r]) for r in refs]
        # Ориентация контура: по знаку площади — чтобы найти "наружу".
        area2 = sum(x1 * z2 - x2 * z1 for (x1, z1), (x2, z2) in zip(pts, pts[1:]))
        for (ax, az), (bx, bz) in zip(pts, pts[1:]):
            length = math.hypot(bx - ax, bz - az)
            if length < MIN_WALL:
                continue
            ux, uz = (bx - ax) / length, (bz - az) / length
            # Наружная нормаль: для обхода против часовой (area2 > 0) — вправо.
            nx, nz = (uz, -ux) if area2 > 0 else (-uz, ux)
            mx, mz = (ax + bx) / 2, (az + bz) / 2
            best = None
            for a, b in streets:
                d, cx, cz = seg_point_distance(mx, mz, a["x"], a["z"], b["x"], b["z"])
                if best is None or d < best[0]:
                    best = (d, cx, cz)
            if best is None or not (STREET_MIN <= best[0] <= STREET_MAX):
                continue
            # Стена должна смотреть на улицу, а не боком/спиной.
            facing = ((best[1] - mx) * nx + (best[2] - mz) * nz) / best[0]
            if facing < 0.75:
                continue
            candidates.append({
                "x": round(mx, 2), "z": round(mz, 2),
                "nx": round(nx, 4), "nz": round(nz, 4),
                "wall": round(length, 2),
                "street": round(best[0], 2),
            })

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(candidates, f)
    print(f"Неон: {len(candidates)} кандидатов на стенах вдоль улиц -> {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
