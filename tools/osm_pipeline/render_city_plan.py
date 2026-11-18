#!/usr/bin/env python3
"""Local overview: mapped footprints plus explicitly approximate dressing."""
import json, math, xml.etree.ElementTree as ET
from pathlib import Path
from build_road_graph import project

base=Path(__file__).resolve().parents[2]
m=json.loads((base/'assets/data/city_map.json').read_text())
c=json.loads((base/'tools/osm_pipeline/calibration.json').read_text())
root=ET.parse(base/'tools/osm_pipeline/sources/yuzhny_streets_2026-11-18.osm').getroot()
nodes={n.get('id'):project(c,float(n.get('lat')),float(n.get('lon'))) for n in root.findall('node')}
def pt(p):return f'{p[0]+520:.2f},{520-p[1]:.2f}'
def points(ps):return ' '.join(map(pt,ps))
s=['<svg xmlns="http://www.w3.org/2000/svg" width="1120" height="1230" viewBox="-40 -60 1120 1230"><rect x="-40" y="-60" width="1120" height="1230" fill="#e4e8da"/><defs><clipPath id="map"><rect width="1040" height="1040"/></clipPath></defs><g clip-path="url(#map)">']
for w in root.findall('way'):
 t={v.get('k'):v.get('v') for v in w.findall('tag')};p=[nodes[v.get('ref')] for v in w.findall('nd') if v.get('ref') in nodes]
 if 'building' in t:s.append(f'<polygon points="{points(p)}" fill="#aca594" stroke="#8c8578" stroke-width=".6"/>')
 elif t.get('highway') not in (None,'footway','path','cycleway'):s.append(f'<polyline points="{points(p)}" fill="none" stroke="#868c8c" stroke-width="{4 if t["highway"]=="service" else 7}"/>')
for a in m['areas']:s.append(f'<polygon points="{points(a["points"])}" fill="#789d94" stroke="#345a54"/>')
for p in m['paths']+m.get('accessPaths',[]):s.append(f'<polyline points="{points(p["points"])}" fill="none" stroke="#faf8e9" stroke-width="2.3"/>')
for f in m['fixtures']:
 x,y=pt(f['point']).split(',');color={'tree':'#386943','lamp':'#e3a218','porch_light':'#b77512','bench':'#855334','block':'#323842','waste_basket':'#303a32'}[f['kind']]
 s.append(f'<circle cx="{x}" cy="{y}" r="{3 if f["kind"]=="tree" else 2.3}" fill="{color}"/>')
for f in m.get('barriers',[]):
 for section in f.get('sections',[]):s.append(f'<polyline points="{points([section["a"],section["b"]])}" fill="none" stroke="#244839" stroke-width="1.7"/>')
for e in m.get('equipment',[]):
 ps=[]
 for x,z in [(-1,-1),(1,-1),(1,1),(-1,1)]:
  dx=x*e['width']/2;dz=z*e['length']/2;v=e['yaw'];ps.append([e['point'][0]+math.cos(v)*dx+math.sin(v)*dz,e['point'][1]-math.sin(v)*dx+math.cos(v)*dz])
 s.append(f'<polygon points="{points(ps)}" fill="#527eaf" stroke="#2b415b" stroke-width=".6"/>')
s+=['</g><text x="0" y="-25" font-family="sans-serif" font-size="23">Южный · благоустройство игрового квартала</text>']
for i,line in enumerate(['Светлые линии: дорожки OSM · зелёные контуры: площадки OSM','Точки фонарей / лавочек / деревьев / урн — приблизительные','Ограды и синее оборудование внутри площадок — приблизительные','© OpenStreetMap contributors · ODbL · снимок 18.11.2026 · север ↑']):
 s.append(f'<text x="0" y="{1075+i*25}" font-family="sans-serif" font-size="16">{line}</text>')
s.append('</svg>');(base/'docs/CITY_MAP.svg').write_text(''.join(s))
