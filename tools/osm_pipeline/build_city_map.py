#!/usr/bin/env python3
"""Reproducible OSM street inventory; surveyed geometry and inferred dressing stay separate."""
import json, math, sys, xml.etree.ElementTree as ET
from build_road_graph import project


def build(source, calibration):
    root = ET.parse(source).getroot()
    nodes = {n.get('id'): n for n in root.findall('node')}
    def tags(e): return {t.get('k'): t.get('v') for t in e.findall('tag')}
    def point(n): return [round(v, 3) for v in project(calibration, float(n.get('lat')), float(n.get('lon')))]
    paths, areas, barriers, fixtures = [], [], [], []
    for way in root.findall('way'):
        t = tags(way)
        pts = [point(nodes[n.get('ref')]) for n in way.findall('nd') if n.get('ref') in nodes]
        entry = dict(osm='way/'+way.get('id'), tags=t, points=pts, placement='mapped')
        if t.get('highway') in ('footway', 'pedestrian', 'path') and len(pts)>1:
            try: width = max(1., min(6., float(t.get('width', 2.))))
            except ValueError: width=2.
            paths.append(dict(entry, width=width, widthSource='mapped' if 'width' in t else 'default'))
        if t.get('leisure') in ('park','garden','playground','pitch','fitness_station') and len(pts)>2: areas.append(entry)
        if t.get('barrier') in ('fence','wall','hedge') and len(pts)>1: barriers.append(entry)
    for n in root.findall('node'):
        t=tags(n)
        kind = ('lamp' if t.get('highway')=='street_lamp' else
                'tree' if t.get('natural')=='tree' else
                t.get('amenity') if t.get('amenity') in ('bench','fountain','waste_basket','drinking_water') else
                'block' if t.get('barrier')=='block' else None)
        if kind: fixtures.append(dict(osm='node/'+n.get('id'), kind=kind, point=point(n), tags=t, placement='mapped', yaw=0))
    return dict(schema=1, source='https://api.openstreetmap.org/api/0.6/map?bbox=55.09994,51.71102,55.11444,51.72000',
                snapshot='2026-11-18', attribution='© OpenStreetMap contributors · ODbL 1.0',
                coordinates='calibration.json; game X east, Z north, metres', paths=paths, areas=areas, barriers=barriers, fixtures=fixtures)

if __name__=='__main__':
    result=build(sys.argv[1],json.load(open(sys.argv[2])))
    with open(sys.argv[3],'w') as f:json.dump(result,f,ensure_ascii=False,indent=2)
    print({k:len(result[k]) for k in ('paths','areas','barriers','fixtures')})
