import assert from 'node:assert/strict';
import fs from 'node:fs';
import {inside,nearestPath,distance,projectToSegment} from './city_area_layout.mjs';
const map=JSON.parse(fs.readFileSync('assets/data/city_map.json'));
for(const item of map.equipment) {
 const area=map.areas.find(a=>a.osm===item.basis);
 assert.equal(item.placement,'inferred');
 for(const x of [-item.width/2,item.width/2])for(const z of [-item.length/2,item.length/2]) {
  const p=[item.point[0]+Math.cos(item.yaw)*x+Math.sin(item.yaw)*z,item.point[1]-Math.sin(item.yaw)*x+Math.cos(item.yaw)*z];
  assert(inside(p,area.points),'equipment outside mapped footprint: '+item.kind);
 }
}
for(const f of map.barriers)for(const s of f.sections??[]) {
 const count=Math.ceil(distance(s.a,s.b)/.15);
 for(let i=0;i<=count;i++) {
  const p=s.a.map((v,k)=>v+(s.b[k]-v)*i/count),route=nearestPath(p,map.paths);
  assert(route.distance>route.width/2+.55,'fence blocks a mapped path');
 }
 assert(distance(projectToSegment(f.gate.point,s.a,s.b),f.gate.point)>1.6,'narrow gate');
}
assert.equal(map.equipment.length,7);
assert.equal(map.barriers.filter(f=>f.type!=='courtyard').length,3);
assert.equal(map.barriers.filter(f=>f.type==='courtyard').length,8);
assert.equal(map.startBlock.buildings.length,8);
assert.equal(map.parking.length,8);
console.log('PASS: seven equipment footprints fit; three fences retain gates and mapped paths');
