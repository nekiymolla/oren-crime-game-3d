#!/usr/bin/env python3
"""Authored sample block, constrained by the existing OSM footprints/streets."""
import json,math,xml.etree.ElementTree as ET
from pathlib import Path
from build_road_graph import project
root=Path(__file__).resolve().parents[2]
cal=json.loads((root/'tools/osm_pipeline/calibration.json').read_text())
osm=ET.parse(root/'tools/osm_pipeline/sources/yuzhny_streets_2026-11-18.osm').getroot()
nodes={n.get('id'):project(cal,float(n.get('lat')),float(n.get('lon'))) for n in osm.findall('node')}
ways=[]
for w in osm.findall('way'):
 tags={t.get('k'):t.get('v') for t in w.findall('tag')}
 points=[nodes[n.get('ref')] for n in w.findall('nd') if n.get('ref') in nodes]
 ways.append(dict(osm='way/'+w.get('id'),tags=tags,points=points))
def nearest(p,a,b):
 dx,dz=b[0]-a[0],b[1]-a[1];t=max(0,min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dz)/(dx*dx+dz*dz)))
 return [a[0]+dx*t,a[1]+dz*t]
roads=[(a,b) for w in ways if w['tags'].get('highway') in ('tertiary','residential') for a,b in zip(w['points'],w['points'][1:])]
profiles=[]
palettes=[[.38,.20,.12],[.44,.39,.29],[.35,.29,.21],[.29,.36,.32],[.31,.18,.115],[.46,.43,.35],[.41,.32,.22],[.32,.37,.39]]
for w in ways:
 if 'building' not in w['tags'] or len(w['points'])<4:continue
 ps=w['points'][:-1];lo=[min(p[i] for p in ps) for i in (0,1)];hi=[max(p[i] for p in ps) for i in (0,1)];center=[(lo[i]+hi[i])/2 for i in (0,1)]
 if not(-65<center[0]<18 and 30<center[1]<100):continue
 candidates=[]
 for a,b in zip(ps,ps[1:]+ps[:1]):
  length=math.dist(a,b)
  if length<5:continue
  mid=[(a[i]+b[i])/2 for i in (0,1)];n=[-(b[1]-a[1])/length,(b[0]-a[0])/length]
  if sum(n[i]*(mid[i]-center[i]) for i in (0,1))<0:n=[-v for v in n]
  q=min((nearest(mid,c,d) for c,d in roads),key=lambda p:math.dist(mid,p))
  if sum(n[i]*(q[i]-mid[i]) for i in (0,1))>1:candidates.append((math.dist(mid,q),mid,n,a,b))
 if not candidates:continue
 _,mid,n,a,b=min(candidates,key=lambda x:x[0]);t=[-n[1],n[0]];bay=2.7
 # Align the actual door model and the procedural shader to the same bay.
 u=(math.floor(sum(mid[i]*t[i] for i in (0,1))/bay)+.5)*bay
 offset=u-sum(mid[i]*t[i] for i in (0,1));door=[mid[i]+t[i]*offset for i in (0,1)]
 profiles.append(dict(osm=w['osm'],tags=w['tags'],outline=w['points'],center=center,bounds=[lo,hi],front=[*door,*n],bayWidth=bay,placement='inferred',basis=w['osm']))
profiles.sort(key=lambda p:(p['center'][0]>-20,p['center'][1]))
parcels=[]
for row in [profiles[:4],profiles[4:]]:
 for i,p in enumerate(row):
  idx=profiles.index(p);p.update(style=idx%2,wallColor=palettes[idx],roofColor=[[.19,.23,.22],[.27,.17,.13],[.21,.23,.25]][idx%3],variation=.12+idx*.105)
  lo,hi=p['bounds'];z0=(row[i-1]['center'][1]+p['center'][1])/2 if i else min(q['bounds'][0][1] for q in row)-3
  z1=(p['center'][1]+row[i+1]['center'][1])/2 if i+1<len(row) else max(q['bounds'][1][1] for q in row)+3
  x0=lo[0]-2.5 if p['center'][0]<-20 else -20
  x1=-24 if p['center'][0]<-20 else hi[0]+2.2
  d=p['front'][:2];n=p['front'][2:];ts=[]
  for axis,bound in [(0,x0),(0,x1),(1,z0),(1,z1)]:
   if abs(n[axis])>.01:
    amount=(bound-d[axis])/n[axis]
    if amount>0:ts.append(amount)
  amount=min(ts);gate=[d[j]+n[j]*amount for j in (0,1)]
  outline=[[x0,z0],[x1,z0],[x1,z1],[x0,z1],[x0,z0]]
  # Rear service court: architecture is drawn later only in clear cells.
  yard=[(hi[0]+x1)/2 if p['center'][0]<-20 else (x0+lo[0])/2,p['center'][1]]
  back=[x1,p['center'][1]] if p['center'][0]<-20 else [x0,p['center'][1]]
  parking=[x1-3,p['center'][1]] if p['center'][0]<-20 else [x0+3,p['center'][1]]
  shed=[yard[0],z1-2.2]
  parcels.append(dict(basis=p['osm'],placement='inferred',outline=outline,gate=gate,gates=[gate,back],gateWidth=3.6,entrance=d,normal=n,yard=yard,parking=parking,shed=shed))
result=dict(name='Илекская — Сумская, севернее Весенней',source='OSM snapshot 2026-11-18; geometry mapped, all facade/courtyard dressing inferred',buildings=profiles,parcels=parcels,serviceLane=dict(points=[[-22,29],[-22,103]],width=3.1,placement='inferred'))
(root/'assets/data/start_block.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
print('Start block:',len(profiles),'buildings,',len(parcels),'courtyards')
