// Verify exported game assets, including reflection/winding and finite extents.
import fs from 'node:fs';
import {NodeIO} from '@gltf-transform/core';
const io=new NodeIO();let triangles=0;
for(const file of fs.readdirSync('assets/models/world/streets').filter(f=>f.endsWith('.glb'))) {
 const doc=await io.read('assets/models/world/streets/'+file);
 for(const mesh of doc.getRoot().listMeshes()) for(const p of mesh.listPrimitives()) {
  const pos=p.getAttribute('POSITION'),norm=p.getAttribute('NORMAL'),idx=p.getIndices();
  const count=idx?.getCount()??pos.getCount();
  for(let i=0;i<count;i+=3) {
   const ids=[0,1,2].map(j=>idx?idx.getScalar(i+j):i+j);
   const v=ids.map(id=>pos.getElement(id,[]));
   for(const a of v)if(!a.every(Number.isFinite)||Math.abs(a[0])>2000||Math.abs(a[2])>2000||a[1]<-.2||a[1]>8)throw new Error('Invalid bounds '+file);
   const u=v[1].map((n,k)=>n-v[0][k]),w=v[2].map((n,k)=>n-v[0][k]);
   const cross=[u[1]*w[2]-u[2]*w[1],u[2]*w[0]-u[0]*w[2],u[0]*w[1]-u[1]*w[0]];
   const n=norm.getElement(ids[0],[]),length=Math.hypot(...cross);
   if(length>1e-8 && cross.reduce((s,x,k)=>s+x*n[k],0)/length<.98)throw new Error('Reversed normal '+file+' '+mesh.getName());
   triangles++;
  }
 }
}
console.log('PASS: finite street geometry, bounded heights and consistent normals: '+triangles+' triangles');
