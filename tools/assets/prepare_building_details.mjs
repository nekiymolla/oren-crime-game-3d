// Overlay geometry from the existing OSM wall outlines. No source geometry is
// overwritten. Game coordinates (+Z north) are converted to glTF at export.
// node tools/assets/prepare_building_details.mjs <chunksDir> <outputDir>
import {NodeIO, Document} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
import {getBounds, weld, prune} from '@gltf-transform/functions';
import fs from 'node:fs';
import path from 'node:path';
const [input, output] = process.argv.slice(2);
if (!input || !output) throw new Error('Expected chunks and output directories');
fs.mkdirSync(output, {recursive:true});
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const manifest = JSON.parse(fs.readFileSync(path.join(input,'manifest.json')));
const fract=x=>x-Math.floor(x);
const seedFor=(x,z)=>fract(Math.sin(Math.floor(x)*12.9898+Math.floor(z)*78.233)*43758.5453);
const summary=[];
const profiles=JSON.parse(fs.readFileSync('assets/data/start_block.json')).buildings;
for (const cell of manifest.cells) {
  const src=await io.read(path.join(input,cell.file));
  const doc=new Document(), buf=doc.createBuffer(), scene=doc.createScene();
  const buckets = new Map();
  function bucket(name, color) {
    if (!buckets.has(name)) buckets.set(name,{positions:[], normals:[], colors:[],color});
    return buckets.get(name);
  }
  function tri(b,a,c,d,color=b.color) {
    const ab=c.map((v,i)=>v-a[i]), ac=d.map((v,i)=>v-a[i]);
    let n=[ab[1]*ac[2]-ab[2]*ac[1],ab[2]*ac[0]-ab[0]*ac[2],ab[0]*ac[1]-ab[1]*ac[0]];
    const len=Math.hypot(...n); if(len<1e-8)return;
    n=n.map(v=>v/len);
    for(const p of [a,d,c]) { // reflection in Z reverses winding
      b.positions.push(p[0],p[1],-p[2]);
      b.normals.push(n[0],n[1],-n[2]); b.colors.push(...color,1);
    }
  }
  function box(b,center,u,n,width,height,depth,color) {
    const p=[];
    for(const y of [-1,1]) for(const z of [-1,1]) for(const x of [-1,1])
      p.push(center.map((v,i)=>v+u[i]*x*width/2+n[i]*z*depth/2+(i===1?y*height/2:0)));
    for(const [a,c,d,e] of [[4,6,7,5],[2,3,7,6],[0,2,6,4],[1,5,7,3]]) {
      tri(b,p[a],p[c],p[d],color); tri(b,p[a],p[d],p[e],color);
    }
  }
  const trim=bucket('MasonryTrim',[.59,.56,.49]);
  const roof=bucket('RoofMetal',[.18,.21,.20]);
  const metal=bucket('MetalDetails',[.16,.17,.16]);
  const porch=bucket('Porches',[.19,.22,.20]);
  const lamps=bucket('CityLampGlow',[1,.73,.4]);
  let buildings=0, pitched=0;
  for(const node of src.getRoot().listNodes()) {
    const mesh=node.getMesh(); if(!mesh)continue;
    if(!mesh.listPrimitives().some(p=>['Plaster002','Concrete034'].includes(p.getMaterial()?.getName())))continue;
    const bounds=getBounds(node), base=bounds.min[1], top=bounds.max[1], height=top-base;
    if(height<2.5)continue;
    if(!Number.isFinite(height)||top>1000)throw new Error('Calibration geometry in input: '+cell.file);
    const minX=bounds.min[0], minZ=-bounds.max[2];
    const seed=seedFor(minX,minZ);
    const profile=profiles.find(p=>Math.hypot(p.center[0]-(bounds.min[0]+bounds.max[0])/2,p.center[1]+(bounds.min[2]+bounds.max[2])/2)<1);
    const style=profile?.style??Math.min(2,Math.floor(seed*3));
    const bay=profile?.bayWidth??(style===2?3.3:2.7), floorHeight=height/Math.max(1,Math.round(height/3.4));
    const center=[(bounds.min[0]+bounds.max[0])/2,0,-(bounds.min[2]+bounds.max[2])/2];
    const segments=[],seen=new Set();
    for(const p of mesh.listPrimitives()) {
      if(!['Plaster002','Concrete034'].includes(p.getMaterial()?.getName()))continue;
      const pos=p.getAttribute('POSITION'), ind=p.getIndices()?.getArray()??Array.from({length:pos.getCount()},(_,i)=>i);
      for(let i=0;i<ind.length;i+=3) {
        const verts=[0,1,2].map(j=>pos.getElement(ind[i+j],[])).filter(v=>Math.abs(v[1]-base)<.04);
        if(verts.length!==2)continue;
        let [a,b]=verts.map(v=>[v[0],v[1],-v[2]]);
        const key=[a,b].map(v=>v.map(c=>c.toFixed(2)).join(',')).sort().join(':');
        if(seen.has(key))continue; seen.add(key);
        const length=Math.hypot(b[0]-a[0],b[2]-a[2]); if(length<1)continue;
        let u=[(b[0]-a[0])/length,0,(b[2]-a[2])/length], n=[-u[2],0,u[0]];
        if(n[0]*((a[0]+b[0])/2-center[0])+n[2]*((a[2]+b[2])/2-center[2])<0) n=n.map(v=>-v);
        // Matches shader t = (-normal.z, normal.x).
        u=[-n[2],0,n[0]];
        segments.push({a,b,u,n,length});
        const mid=[(a[0]+b[0])/2,top-.14,(a[2]+b[2])/2];
        box(trim,mid,u,n,length+.18,.26,.35);
        box(trim,[mid[0],base+.3,mid[2]],u,n,length,.6,.14,[.25,.25,.23]);
        if(style===0)box(trim,[mid[0],base+floorHeight,mid[2]],u,n,length,.16,.22);
        const ua=a[0]*u[0]+a[2]*u[2], ub=b[0]*u[0]+b[2]*u[2];
        const lo=Math.min(ua,ub),hi=Math.max(ua,ub);
        for(let f=0;f<Math.round(height/floorHeight);f++) {
          for(let k=Math.floor(lo/bay);k<=Math.ceil(hi/bay);k++) {
            if(f===0 && style!==2 && k===Math.floor(((profile?profile.front[0]:center[0])*u[0]+(profile?profile.front[1]:center[2])*u[2])/bay) && (!profile || n[0]*profile.front[2]+n[2]*profile.front[3]>.9))continue;
            const along=(k+.5)*bay;
            const w=style===2?1.65:1.25;
            if(along-w/2<lo+.35||along+w/2>hi-.35)continue;
            const t=(along-ua)/(ub-ua);
            const x=a[0]+(b[0]-a[0])*t,z=a[2]+(b[2]-a[2])*t;
            const point=(y,out=.07)=>[x+n[0]*out,y,z+n[2]*out];
            const bottom=base+f*floorHeight+1, winTop=base+f*floorHeight+2.45;
            box(trim,point(bottom-.07,.12),u,n,w+.24,.14,.34);
            if(profile) {
              box(trim,point(winTop+.045,.075),u,n,w+.16,.09,.16,[.56,.54,.49]);
              for(const side of [-1,1]) {
                const q=point((bottom+winTop)/2,.055);
                q[0]+=u[0]*side*(w/2+.045);q[2]+=u[2]*side*(w/2+.045);
                box(trim,q,u,n,.085,winTop-bottom,.12,[.52,.51,.46]);
              }
            }

          }
        }
        // A narrow rainwater pipe on each substantial facade.
        if(length>7) box(metal,[a[0]+(b[0]-a[0])*.06+n[0]*.14,(base+top)/2,a[2]+(b[2]-a[2])*.06+n[2]*.14],u,n,.085,height,.085);
      }
    }
    if(profile) {
      const [x,z,nx,nz]=profile.front,u=[-nz,0,nx],n=[nx,0,nz];
      const point=(along,y,out)=>[x+u[0]*along+n[0]*out,base+y,z+u[2]*along+n[2]*out];
      box(porch,point(0,1.18,.065),u,n,1.04,2.32,.10,[.075,.10,.09]);
      for(const side of [-1,1])box(trim,point(side*.6,1.2,.13),u,n,.15,2.4,.23,[.48,.46,.40]);
      box(trim,point(0,2.44,.13),u,n,1.35,.17,.26);
      box(metal,point(.34,1.05,.14),u,n,.055,.23,.06,[.45,.42,.33]);
      box(porch,point(0,.075,.65),u,n,1.75,.15,1.2,[.34,.34,.31]);
      box(porch,point(0,2.62,.68),u,n,1.95,.12,1.55,profile.roofColor);
      for(const side of [-1,1])box(metal,point(side*.85,2.37,.7),u,n,.05,.5,.05);
      box(porch,point(.88,1.45,.15),u,n,.30,.37,.13,[.18,.22,.20]);
      box(metal,point(.88,1.52,.23),u,n,.18,.025,.02);
      box(metal,point(0,2.32,.22),u,n,.22,.32,.20);
      box(lamps,point(0,2.32,.33),u,n,.16,.23,.025);
    }
    buildings++;
    // Only rectangular, modest buildings receive a fitted pitched roof.
    // Complex and large footprints keep the original OSM roof.
    if(style!==2 && segments.length===4 && height<12) {
      const edge=segments.reduce((a,b)=>a.length>b.length?a:b),u=edge.u,n=edge.n;
      const points=segments.flatMap(s=>[s.a,s.b]);
      const us=points.map(p=>p[0]*u[0]+p[2]*u[2]),vs=points.map(p=>p[0]*n[0]+p[2]*n[2]);
      const u0=Math.min(...us)-.25,u1=Math.max(...us)+.25,v0=Math.min(...vs)-.25,v1=Math.max(...vs)+.25;
      const area=(u1-u0-.5)*(v1-v0-.5);
      // Segment winding is not guaranteed; use orthogonality instead.
      const rectangular=segments.every(e=>Math.abs(e.u[0]*u[0]+e.u[2]*u[2])<.01||Math.abs(e.u[0]*u[0]+e.u[2]*u[2])>.99);
      if(rectangular && area<1000 && v1-v0<28) {
        const ridge=top+Math.min(2.6,(v1-v0)*.22),vmid=(v0+v1)/2;
        const p=(a,b,y)=>[u[0]*a+n[0]*b,y,u[2]*a+n[2]*b];
        const A=p(u0,v0,top+.04),B=p(u1,v0,top+.04),C=p(u0,vmid,ridge),D=p(u1,vmid,ridge),E=p(u0,v1,top+.04),F=p(u1,v1,top+.04);
        const colors=[[.23,.27,.25],[.31,.18,.14],[.23,.25,.28]];
        const color=profile?.roofColor??colors[Math.floor(seed*19)%3];
        for(const [a,b,c] of [[A,C,B],[B,C,D],[C,E,D],[D,E,F],[A,E,C],[B,D,F]])tri(roof,a,b,c,color);
        if(profile) {
          const q=p((u0+u1)/2+1,vmid,top+1.4);
          box(trim,q,u,n,.45,2.7,.55,[.30,.19,.14]);
          box(metal,[q[0],top+2.8,q[2]],u,n,.62,.09,.7);
        }
        pitched++;
      }
    }
  }
  for(const [name,b] of buckets) {
    if(!b.positions.length)continue;
    const material=doc.createMaterial(name).setBaseColorFactor([1,1,1,1]).setRoughnessFactor(name==='RoofMetal'?.75:.9).setDoubleSided(true);
    const acc=(type,array)=>doc.createAccessor().setType(type).setArray(new Float32Array(array)).setBuffer(buf);
    if(name==='CityLampGlow')material.setEmissiveFactor([1,.73,.4]);
    const prim=doc.createPrimitive().setAttribute('POSITION',acc('VEC3',b.positions)).setAttribute('NORMAL',acc('VEC3',b.normals)).setAttribute('COLOR_0',acc('VEC4',b.colors)).setMaterial(material);
    scene.addChild(doc.createNode(name).setMesh(doc.createMesh().addPrimitive(prim)));
  }
  await doc.transform(weld(), prune());
  await io.write(path.join(output,cell.file),doc);
  summary.push({file:cell.file,buildings,pitched,triangles:[...buckets.values()].reduce((s,b)=>s+b.positions.length/9,0)});
}
fs.writeFileSync(path.join(output,'manifest.json'),JSON.stringify(summary,null,2));
console.log(JSON.stringify({chunks:summary.length,buildings:summary.reduce((s,b)=>s+b.buildings,0),pitched:summary.reduce((s,b)=>s+b.pitched,0),triangles:summary.reduce((s,b)=>s+b.triangles,0)}));
