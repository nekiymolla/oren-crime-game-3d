// OSM positions are authoritative. Additional lamps/benches are explicitly
// inferred street dressing, never promoted to surveyed map objects.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {Document, NodeIO} from '@gltf-transform/core';
import {weld, prune} from '@gltf-transform/functions';
import {loadChunkGeometry} from '../osm_pipeline/chunk_geometry.mjs';
import {planAreas} from './city_area_layout.mjs';
import {buildAreaGeometry} from './city_area_geometry.mjs';
import {planStartBlock,buildStartBlock} from './start_block_geometry.mjs';
const dir='assets/models/world/streets';
fs.mkdirSync(dir,{recursive:true});
const map=JSON.parse(fs.readFileSync('assets/data/city_map.json'));
map.fixtures=map.fixtures.filter(f=>f.placement==='mapped');
const meta=JSON.parse(fs.readFileSync('assets/data/minimap.json'));
const nav=fs.readFileSync('assets/data/nav_grid.bin');
function kind(x,z) {
 const i=Math.floor((x-meta.minX)/meta.nav.metersPerCell),j=Math.floor((z-meta.minZ)/meta.nav.metersPerCell);
 return i<0||j<0||i>=meta.nav.width||j>=meta.nav.height?4:nav[j*meta.nav.width+i];
}
const geometry=await loadChunkGeometry('assets/models/world/chunks');
function height(x,z) { const s=geometry.topSurfaceAt(x,z); return s&&s.y<1?s.y:0; }
function clear(x,z,r=.6) {for(const [dx,dz] of [[0,0],[r,0],[-r,0],[0,r],[0,-r]])if(![0,3].includes(kind(x+dx,z+dz)))return false;return true;}
const near=(a,b,d)=>Math.hypot(a[0]-b[0],a[1]-b[1])<d;
// Sample along complete ways, not every short segment, so OSM vertex density
// cannot create a cluster of poles. Corners retain their source direction.
for(const way of map.paths) {
 let distance=0,nextLamp=12,nextBench=28,nextTree=20;
 for(let i=1;i<way.points.length;i++) {
  const a=way.points[i-1],b=way.points[i],len=Math.hypot(b[0]-a[0],b[1]-a[1]);
  if(len<.1)continue;
  const u=[(b[0]-a[0])/len,(b[1]-a[1])/len],n=[-u[1],u[0]];
  function place(kindName,at,side) {
   const t=(at-distance)/len;
   const p=[a[0]+u[0]*len*t+n[0]*(way.width/2+side),a[1]+u[1]*len*t+n[1]*(way.width/2+side)];
   if(!clear(...p,kindName==='bench'?1:.5))return;
   if(map.fixtures.some(f=>f.kind===kindName&&near(f.point,p,kindName==='lamp'?24:38)))return;
   if(map.fixtures.filter(f=>f.kind===kindName).length>=(kindName==='lamp'?120:40))return;
   map.fixtures.push({kind:kindName,point:p.map(v=>+v.toFixed(3)),yaw:Math.atan2(-n[0],-n[1]),placement:'inferred',basis:way.osm,reason:'Street dressing beside mapped footway; exact real-world fixture position unverified'});
  }
  while(nextLamp<distance+len){place('lamp',nextLamp,.65);nextLamp+=34;}
  while(nextBench<distance+len){place('bench',nextBench,1.15);nextBench+=70;}
  while(nextTree<distance+len){
   const t=(nextTree-distance)/len;
   for(const side of [-1,1]) {
    const p=[a[0]+u[0]*len*t+n[0]*side*(way.width/2+4.2),a[1]+u[1]*len*t+n[1]*side*(way.width/2+4.2)];
    if(map.fixtures.filter(f=>f.kind==='tree').length<100 && kind(...p)===0 && clear(...p,2.9) && !map.fixtures.some(f=>near(f.point,p,f.kind==='tree'?8:5)))
      map.fixtures.push({kind:'tree',point:p.map(v=>+v.toFixed(3)),yaw:0,placement:'inferred',basis:way.osm,reason:'Authored planting beside mapped path; individual tree position unverified'});
   }
   nextTree+=22;
  }
  distance+=len;
 }
}
for(const f of map.fixtures) f.y=+height(...f.point).toFixed(3);
for(const area of map.areas) {
 const pts=area.points.slice(0,-1);
 area.center=[0,1].map(i=>+(pts.reduce((s,p)=>s+p[i],0)/pts.length).toFixed(3));
}
const areas=planAreas(map,{clear:(x,z)=>clear(x,z,.25),height});
map.barriers=[...(map.barriers??[]).filter(b=>b.placement==='mapped'),...areas.fences];
map.equipment=areas.equipment;
const startBlock=JSON.parse(fs.readFileSync('assets/data/start_block.json'));
const startDressing=planStartBlock(startBlock,{clear,height});
map.startBlock=startBlock;
map.parking=startDressing.parking;
map.barriers.push(...startDressing.fences);
map.fixtures.push(...startDressing.fixtures);
map.accessPaths=areas.fences.filter(f=>f.gate.distance>.5).map(f=>({points:[f.gate.path,f.gate.point],width:2.4,placement:'inferred',basis:f.basis,reason:'Authored access from mapped path to approximate entrance'}));
// Bins belong beside a bench, not in the walking corridor.
for(const [i,bench] of map.fixtures.filter(f=>f.kind==='bench').entries()) {
 if(i%3!==0)continue;
 const p=[bench.point[0]+Math.cos(bench.yaw)*1.55,bench.point[1]-Math.sin(bench.yaw)*1.55];
 if(!clear(...p,.5)||map.fixtures.some(f=>near(f.point,p,f.kind==='tree'?3.2:.8)))continue;
 map.fixtures.push({kind:'waste_basket',point:p,y:height(...p),yaw:bench.yaw,placement:'inferred',basis:bench.basis,reason:'Authored litter bin beside bench; real position unverified'});
}
const manifest=JSON.parse(fs.readFileSync('assets/models/world/chunks/manifest.json'));
const cells=new Map(manifest.cells.map(c=>[c.id,{cell:c,buckets:new Map()}]));
// Actual manifest IDs include the prefix? Resolve by cell coordinates.
function target(x,z){return [...cells.values()].find(c=>c.cell.cellX===Math.floor(x/200)&&c.cell.cellZ===Math.floor(z/200));}
const surfaceGrain=execFileSync('python3',['tools/assets/prepare_urban_grain.py']);
const colors={CityPaving:[.46,.45,.41],CityCurbs:[.63,.62,.57],CityMetal:[.16,.19,.18],CityWood:[.31,.19,.105],CitySolid:[.40,.41,.38],CityLampGlow:[1,.76,.4],CitySport:[.22,.31,.25],CityFence:[.14,.21,.18],CityEquipment:[.22,.29,.26],CityRubber:[.12,.14,.13],CityMarkings:[.72,.72,.65],CityRamp:[.42,.43,.4],CityShrubs:[.13,.24,.11],CityCourtSurface:[.24,.28,.26],CitySkateSurface:[.56,.57,.53]};
function tri(c,name,a,b,d,color=colors[name]){
 if(!c)return;
 let bucket=c.buckets.get(name);if(!bucket)c.buckets.set(name,bucket={p:[],n:[],c:[]});
 const u=b.map((v,i)=>v-a[i]),v=d.map((v,i)=>v-a[i]);
 const n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]],l=Math.hypot(...n);if(l<1e-9)return;
 for(const p of [a,d,b]) {bucket.p.push(p[0],p[1],-p[2]);bucket.n.push(n[0]/l,n[1]/l,-n[2]/l);bucket.c.push(...color,1);}
}
function box(c,name,x,y,z,w,h,d,yaw=0,color){
 const u=[Math.cos(yaw),-Math.sin(yaw)],n=[Math.sin(yaw),Math.cos(yaw)],p=[];
 for(const dy of [-1,1])for(const dz of [-1,1])for(const dx of [-1,1])p.push([x+u[0]*dx*w/2+n[0]*dz*d/2,y+dy*h/2,z+u[1]*dx*w/2+n[1]*dz*d/2]);
 for(const [a,b,d,e] of [[4,5,7,6],[0,2,3,1],[0,1,5,4],[2,6,7,3],[0,4,6,2],[1,3,7,5]]){tri(c,name,p[a],p[d],p[b],color);tri(c,name,p[a],p[e],p[d],color);}
}
function pole(c,name,x,y,z,r,h) {
 const steps=10;
 for(let i=0;i<steps;i++){
  const a=i/steps*Math.PI*2,b=(i+1)/steps*Math.PI*2;
  const A=[x+Math.cos(a)*r,y,z+Math.sin(a)*r],B=[x+Math.cos(b)*r,y,z+Math.sin(b)*r],C=[A[0],y+h,A[2]],D=[B[0],y+h,B[2]];
  tri(c,name,A,C,B);tri(c,name,B,C,D);tri(c,name,[x,y+h,z],D,C);
 }
}
let curbPieces=0,pavingPieces=0;
for(const way of [...map.paths,...map.accessPaths])for(let i=1;i<way.points.length;i++){
 const a=way.points[i-1],b=way.points[i],dx=b[0]-a[0],dz=b[1]-a[1],len=Math.hypot(dx,dz);if(len<.1)continue;
 const count=Math.ceil(len/1.8),u=[dx/len,dz/len],n=[-u[1],u[0]],yaw=Math.atan2(u[0],u[1]);
 for(let k=0;k<count;k++){
  const t=(k+.5)/count,x=a[0]+dx*t,z=a[1]+dz*t,c=target(x,z),h=height(x,z);
  if(!c||![0,3].includes(kind(x,z)))continue;
  // Thin capped concrete panels follow mapped routes; skip asphalt junctions.
  const shade=(k%3-1)*.025;
  box(c,'CityPaving',x,h+.025,z,way.width-.08,.035,len/count-.025,yaw,colors.CityPaving.map(v=>v+shade));pavingPieces++;
  for(const side of [-1,1]){
   const cx=x+n[0]*side*(way.width/2+.04),cz=z+n[1]*side*(way.width/2+.04);
   if(![0,3].includes(kind(cx,cz)))continue;
   // Do not run a curb across another path; leave accessible openings.
   if(kind(cx+n[0]*side*.35,cz+n[1]*side*.35)===3)continue;
   box(c,'CityCurbs',cx,h+.055,cz,.14,.11,len/count-.035,yaw);curbPieces++;
  }
 }
}
for(const f of map.fixtures){
 const [x,z]=f.point,y=f.y,c=target(x,z);if(!c)continue;
 if(f.kind==='lamp'){
  pole(c,'CitySolid',x,y,z,.075,5.8);pole(c,'CitySolid',x,y,z,.16,.3);
  const n=[Math.sin(f.yaw),Math.cos(f.yaw)];
  box(c,'CityMetal',x+n[0]*.45,y+5.75,z+n[1]*.45,.09,.09,1.1,f.yaw);
  box(c,'CityMetal',x+n[0]*.92,y+5.68,z+n[1]*.92,.36,.15,.75,f.yaw);
  box(c,'CityLampGlow',x+n[0]*.92,y+5.595,z+n[1]*.92,.29,.018,.6,f.yaw);
  f.lightPoint=[x+n[0]*.92,y+5.5,z+n[1]*.92];
 } else if(f.kind==='bench'){
  const p=(dx,dz)=>[x+Math.cos(f.yaw)*dx+Math.sin(f.yaw)*dz,z-Math.sin(f.yaw)*dx+Math.cos(f.yaw)*dz];
  for(const dx of [-.72,.72]){
   const q=p(dx,0);box(c,'CityMetal',q[0],y+.24,q[1],.075,.48,.52,f.yaw);
  }
  for(let s=0;s<4;s++){const q=p(0,-.225+s*.15);box(c,'CityWood',q[0],y+.49,q[1],1.85,.075,.125,f.yaw);}
  for(let s=0;s<3;s++){const q=p(0,-.29);box(c,'CityWood',q[0],y+.72+s*.14,q[1],1.85,.11,.07,f.yaw);}
  // Simple solid seat collider, independent of decorative slats.
  box(c,'CitySolid',x,y+.37,z,1.76,.16,.48,f.yaw);
 }else if(f.kind==='waste_basket') {
  for(const side of [-1,1]) {
   box(c,'CityEquipment',x+Math.cos(f.yaw)*side*.21,y+.38,z-Math.sin(f.yaw)*side*.21,.035,.68,.44,f.yaw);
   box(c,'CityEquipment',x+Math.sin(f.yaw)*side*.21,y+.38,z+Math.cos(f.yaw)*side*.21,.44,.68,.035,f.yaw);
  }
  box(c,'CityRubber',x,y+.13,z,.4,.1,.4,f.yaw);
  box(c,'CityEquipment',x,y+.08,z,.5,.12,.5,f.yaw);
 }else if(f.kind==='block')box(c,'CitySolid',x,y+.35,z,1.6,.7,.65);
}
for(const area of map.areas){
 if(area.tags.leisure!=='fitness_station')continue;
 const [x,z]=area.center,y=height(x,z),c=target(x,z);
 // OSM confirms horizontal bars inside this footprint; exact bar layout inferred.
 for(const dx of [-1,1])pole(c,'CitySport',x+dx,y,z,.055,2.25);
 box(c,'CitySport',x,y+2.22,z,2.1,.07,.07);
}
buildAreaGeometry({map,target,box,pole,tri,height});
buildStartBlock({block:startBlock,target,box,pole,tri,clear,height});
const io=new NodeIO(),summary=[];
for(const {cell,buckets} of cells.values()){
 const doc=new Document(),buffer=doc.createBuffer(),scene=doc.createScene();let triangles=0;
 for(const [name,b] of buckets){
  const material=doc.createMaterial(name).setBaseColorFactor([1,1,1,1]).setRoughnessFactor(name==='CityMetal'?.65:.94).setDoubleSided(true);
  if(name==='CityLampGlow')material.setEmissiveFactor([1,.7,.3]);
  if(name==='CityCourtSurface'||name==='CitySkateSurface')material.setBaseColorTexture(doc.createTexture('Mineral grain').setImage(surfaceGrain).setMimeType('image/png'));
  const acc=(type,data)=>doc.createAccessor().setType(type).setArray(new Float32Array(data)).setBuffer(buffer);
  scene.addChild(doc.createNode(name).setMesh(doc.createMesh(name).addPrimitive(doc.createPrimitive().setMaterial(material).setAttribute('POSITION',acc('VEC3',b.p)).setAttribute('NORMAL',acc('VEC3',b.n)).setAttribute('COLOR_0',acc('VEC4',b.c)))));
  if(name==='CityCourtSurface'||name==='CitySkateSurface') {
   const uv=[];for(let i=0;i<b.p.length;i+=3)uv.push(b.p[i]/2,b.p[i+2]/2);
   scene.listChildren().at(-1).getMesh().listPrimitives()[0].setAttribute('TEXCOORD_0',acc('VEC2',uv));
  }
  triangles+=b.p.length/9;
 }
 await doc.transform(weld(),prune());await io.write(path.join(dir,cell.file),doc);summary.push({file:cell.file,triangles});
}
fs.writeFileSync('assets/data/city_map.json',JSON.stringify(map,null,2));
fs.writeFileSync(path.join(dir,'manifest.json'),JSON.stringify({source:map.source,pavingPieces,curbPieces,fenceSections:map.barriers.reduce((n,f)=>n+(f.sections?.length??0),0),equipment:map.equipment.length,chunks:summary},null,2));
console.log(JSON.stringify({pavingPieces,curbPieces,fixtures:map.fixtures.reduce((o,f)=>(o[f.kind]=(o[f.kind]??0)+1,o),{}),triangles:summary.reduce((s,c)=>s+c.triangles,0)}));
