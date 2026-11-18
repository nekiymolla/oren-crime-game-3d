// Check placement against the shipped map and imported building geometry.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {NodeIO} from '@gltf-transform/core';
import {getBounds} from '@gltf-transform/functions';
import {inside,distance,projectToSegment} from './city_area_layout.mjs';
const map=JSON.parse(fs.readFileSync('assets/data/city_map.json'));
const block=map.startBlock,io=new NodeIO(),matches=new Map(block.buildings.map(b=>[b.osm,0]));
for(const file of fs.readdirSync('assets/models/world/chunks').filter(f=>f.endsWith('.glb'))) {
 const doc=await io.read('assets/models/world/chunks/'+file);
 for(const n of doc.getRoot().listNodes()) {
  if(!n.getMesh()?.listPrimitives().some(p=>['Plaster002','Concrete034'].includes(p.getMaterial()?.getName())))continue;
  const {min,max}=getBounds(n),center=[(min[0]+max[0])/2,-(min[2]+max[2])/2];
  for(const b of block.buildings)if(distance(center,b.center)<1)matches.set(b.osm,matches.get(b.osm)+1);
 }
}
for(const b of block.buildings) {
 assert.equal(matches.get(b.osm),1,'facade must match exactly one imported house: '+b.osm);
 assert.equal(b.placement,'inferred');
 const door=b.front.slice(0,2);
 assert(Math.min(...b.outline.slice(1).map((p,i)=>distance(door,projectToSegment(door,b.outline[i],p))))<.01,'door outside wall');
 const lot=block.parcels.find(p=>p.basis===b.osm),parking=map.parking.find(p=>p.basis===b.osm);
 assert.equal(lot.placement,'inferred');assert.equal(parking.placement,'inferred');
 for(const dx of [-1.5,1.5])for(const dz of [-2.85,2.85]) {
  const p=[parking.point[0]+dx,parking.point[1]+dz];
  assert(inside(p,lot.outline),'parking outside yard');
  assert(!inside(p,b.outline),'parking intersects house');
 }
 for(const gate of lot.gates)assert(inside(gate.map((v,i)=>v*.999+b.center[i]*.001),lot.outline),'gate outside yard');
}
console.log('PASS: eight facades match imported houses; doors meet walls; parking pads fit yards');
