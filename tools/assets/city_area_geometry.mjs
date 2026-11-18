// Muted timber/painted steel rather than brightly coloured toy blocks.
export function buildAreaGeometry({map,target,box,pole,tri,height}) {
 function beam(c,name,a,b,width=.055) {
  const d=b.map((v,i)=>v-a[i]),length=Math.hypot(...d);if(length<.001)return;
  const u=d.map(v=>v/length),v=Math.abs(u[1])<.9?[-u[2],0,u[0]]:[1,0,0],vl=Math.hypot(...v);
  for(let i=0;i<3;i++)v[i]/=vl;
  const w=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]],p=[];
  for(const end of [a,b])for(const sy of [-1,1])for(const sx of [-1,1])p.push(end.map((n,i)=>n+v[i]*sx*width/2+w[i]*sy*width/2));
  // Orient each face against its outward direction so tilted beams keep normals.
  const center=a.map((n,i)=>(n+b[i])/2);
  for(const f of [[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]]) {
   let [A,B,C,D]=f.map(i=>p[i]);
   const ab=B.map((n,i)=>n-A[i]),ac=C.map((n,i)=>n-A[i]);
   const n=[ab[1]*ac[2]-ab[2]*ac[1],ab[2]*ac[0]-ab[0]*ac[2],ab[0]*ac[1]-ab[1]*ac[0]];
   if(n.reduce((s,v,i)=>s+v*((A[i]+B[i]+C[i]+D[i])/4-center[i]),0)<0)[B,D]=[D,B];
   tri(c,name,A,B,C);tri(c,name,A,C,D);
  }
 }
 for(const area of map.areas) {
  if(area.tags.leisure!=='pitch')continue;
  const name=area.tags.sport==='skateboard'?'CitySkateSurface':'CityCourtSurface';
  const points=area.points.slice(0,-1),center=[area.center[0],.018,area.center[1]];
  for(let i=0;i<points.length;i++) {
   let a=[points[i][0],.018,points[i][1]],b=[points[(i+1)%points.length][0],.018,points[(i+1)%points.length][1]];
   const c=target((center[0]+a[0]+b[0])/3,(center[2]+a[2]+b[2])/3);
   if((a[2]-center[2])*(b[0]-center[0])-(a[0]-center[0])*(b[2]-center[2])<0)[a,b]=[b,a];
   tri(c,name,center,a,b);
  }
 }
 for(const fence of map.barriers)for(const section of fence.sections??[]) {
  const {a,b,y}=section,dx=b[0]-a[0],dz=b[1]-a[1],length=Math.hypot(dx,dz),yaw=Math.atan2(dx,dz),c=target((a[0]+b[0])/2,(a[1]+b[1])/2),h=fence.height;
  const point=t=>[a[0]+dx*t,a[1]+dz*t];
  for(const level of [.17,h-.1])box(c,'CityFence',(a[0]+b[0])/2,y+level,(a[1]+b[1])/2,.055,.055,length,yaw);
  const posts=Math.ceil(length/2.2);
  for(let i=0;i<=posts;i++) {const p=point(i/posts);pole(c,'CityFence',p[0],y,p[1],.045,h+.04);}
  const bars=Math.ceil(length/.22);
  for(let i=1;i<bars;i++) {const p=point(i/bars);const wood=fence.style==='timber';box(c,wood?'CityWood':'CityFence',p[0],y+h/2,p[1],wood?.13:.025,h-.1,wood?.045:.025,yaw);}
 }
 for(const item of map.equipment) {
  const [x,z]=item.point,y=item.y,yaw=item.yaw,c=target(x,z);
  const p=(dx,dy,dz)=>[x+Math.cos(yaw)*dx+Math.sin(yaw)*dz,y+dy,z-Math.sin(yaw)*dx+Math.cos(yaw)*dz];
  const localBox=(name,dx,dy,dz,w,h,d,color)=>{const q=p(dx,dy,dz);box(c,name,q[0],q[1],q[2],w,h,d,yaw,color);};
  const localPole=(dx,dz,h,r=.045)=>{const q=p(dx,0,dz);pole(c,'CityEquipment',q[0],q[1],q[2],r,h);};
  const line=(name,a,b,w)=>beam(c,name,p(...a),p(...b),w);
  if(item.kind==='swings') {
   for(const side of [-1,1])for(const front of [-1,1])line('CityEquipment',[side*1.9,0,front*1.15],[side*1.9,2.45,0],.075);
   line('CityEquipment',[-2,2.45,0],[2,2.45,0],.09);
   for(const seat of [-.85,.85]) {
    for(const edge of [-.22,.22])line('CityMetal',[seat+edge,2.4,0],[seat+edge,.55,0],.014);
    localBox('CityRubber',seat,.52,0,.58,.07,.3);
   }
  } else if(item.kind==='slide') {
   for(const dx of [-.65,.65])for(const dz of [-.5,.5])localPole(dx,dz,1.95,.065);
   localBox('CityWood',0,1.2,0,1.5,.13,1.2);
   for(const side of [-1,1]) {
    line('CityEquipment',[side*.7,1.9,-.55],[side*.7,1.9,.55],.06);
    line('CityEquipment',[side*.48,1.28,.5],[side*.48,.25,2.3],.065);
    line('CityEquipment',[side*.45,.2,-2],[side*.45,1.2,-.55],.07);
   }
   for(let i=0;i<5;i++)localBox('CityWood',0,.2+i*.2,-2+i*.3,.9,.07,.27);
   // Sloping slide deck; both directions have support for walking probes.
   line('CityRamp',[-.42,1.2,.55],[-.42,.16,2.3],.035);
   const A=p(-.45,1.2,.55),B=p(.45,1.2,.55),C=p(-.45,.15,2.3),D=p(.45,.15,2.3);
   tri(c,'CityRamp',A,C,B);tri(c,'CityRamp',B,C,D);
  } else if(item.kind==='parallel_bars') {
   for(const dx of [-.6,.6]) {
    for(const dz of [-1,1])localPole(dx,dz,1.25);
    line('CityEquipment',[dx,1.25,-1.15],[dx,1.25,1.15],.06);
   }
  } else if(item.kind==='grind_rail') {
   for(const dz of [-1.1,1.1])localPole(0,dz,.48);
   line('CityEquipment',[0,.48,-1.4],[0,.48,1.4],.075);
  } else if(item.kind==='skate_bank') {
   const direction=item.point[1]<map.areas.find(a=>a.osm===item.basis).center[1]?1:-1;
   // Curved transition and level deck, modest dimensions within the polygon.
   for(let i=0;i<12;i++) {
    const t=i/12,s=(i+1)/12,z0=direction*(-1.7+t*2.6),z1=direction*(-1.7+s*2.6),h0=.045+1.05*t*t,h1=.045+1.05*s*s;
    const A=p(-1.7,h0,z0),B=p(1.7,h0,z0),C=p(-1.7,h1,z1),D=p(1.7,h1,z1);
    if(direction>0){tri(c,'CityRamp',A,C,B);tri(c,'CityRamp',B,C,D);}else{tri(c,'CityRamp',A,B,C);tri(c,'CityRamp',B,D,C);}
    for(const side of [-1,1]) {
     const aa=p(side*1.7,0,z0),bb=p(side*1.7,0,z1),cc=p(side*1.7,h0,z0),dd=p(side*1.7,h1,z1);
     if(side*direction>0){tri(c,'CityRamp',aa,cc,bb);tri(c,'CityRamp',bb,cc,dd);}else{tri(c,'CityRamp',aa,bb,cc);tri(c,'CityRamp',bb,dd,cc);}
    }
   }
   localBox('CityRamp',0,1.055,direction*1.35,3.4,.09,.9);
   localBox('CityRamp',0,.52,direction*1.78,3.4,1.04,.12);
  } else if(item.kind==='court') {
   // Universal court layout is authored, not evidence of basketball in OSM.
   for(const side of [-1,1]) {
    localBox('CityMarkings',side*4.7,.025,0,.075,.012,19);
    localBox('CityMarkings',0,.025,side*9.5,9.4,.012,.075);
    localPole(0,side*8.7,3.6,.09);
    localBox('CityMarkings',0,3.15,side*8.35,1.8,1.05,.07);
    line('CityEquipment',[0,3.2,side*8.7],[0,3.2,side*8.35],.08);
    // A hoop and a restrained wire net.
    for(let i=0;i<16;i++) {
     const a=i/16*Math.PI*2,b=(i+1)/16*Math.PI*2;
     line('CityEquipment',[Math.cos(a)*.23,2.96,side*8.02+Math.sin(a)*.23],[Math.cos(b)*.23,2.96,side*8.02+Math.sin(b)*.23],.025);
     if(i%2===0)line('CityMarkings',[Math.cos(a)*.23,2.94,side*8.02+Math.sin(a)*.23],[Math.cos(a+.2)*.16,2.55,side*8.02+Math.sin(a+.2)*.16],.009);
    }
   }
   localBox('CityMarkings',0,.025,0,9.4,.012,.075);
   for(let i=0;i<40;i++) {
    const a=i/40*Math.PI*2,b=(i+1)/40*Math.PI*2;
    line('CityMarkings',[Math.cos(a)*1.4,.035,Math.sin(a)*1.4],[Math.cos(b)*1.4,.035,Math.sin(b)*1.4],.055);
   }
  }
 }
}
