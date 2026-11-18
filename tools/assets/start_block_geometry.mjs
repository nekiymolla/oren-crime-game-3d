import {nearestPath,distance,projectToSegment} from './city_area_layout.mjs';

export function planStartBlock(block,{clear,height}) {
 const fences=[],surfaces=[],fixtures=[],parking=[];
 for(const [i,lot] of block.parcels.entries()) {
  const p=lot.outline,sections=[];
  for(let edge=0;edge<4;edge++) {
   const a=p[edge],b=p[edge+1],len=distance(a,b),steps=Math.ceil(len/.3);
   let first;
   const at=t=>a.map((v,k)=>v+(b[k]-v)*t);
   for(let j=0;j<steps;j++) {
    const q=at((j+.5)/steps),open=lot.gates.some(g=>distance(q,g)<lot.gateWidth/2+.2)||!clear(...q,.2);
    if(!open&&first===undefined)first=j;
    if(first!==undefined&&(open||j===steps-1)) {
     const last=open?j:j+1;
     if((last-first)*len/steps>.6)sections.push({a:at(first/steps),b:at(last/steps),y:height(...at((first+last)/2/steps))});
     first=undefined;
    }
   }
  }
  fences.push({type:'courtyard',basis:lot.basis,placement:'inferred',reason:'Authored private yard; cadastral boundary and real fence not surveyed',height:1.2,thickness:.08,style:i%2?'metal':'timber',gate:{point:lot.gate,width:3.6},gates:lot.gates,sections});
  parking.push({point:lot.parking,y:0,yaw:0,basis:lot.basis,placement:'inferred'});
  fixtures.push({kind:'porch_light',point:[lot.entrance[0]+lot.normal[0]*.35,lot.entrance[1]+lot.normal[1]*.35],y:0,yaw:Math.atan2(lot.normal[0],lot.normal[1]),basis:lot.basis,placement:'inferred',reason:'Authored entrance luminaire'});
 }
 return {fences,fixtures,parking};
}

export function buildStartBlock({block,target,box,pole,tri,clear,height}) {
 const pavement=(a,b,width,name='CityPaving')=>{
  const len=distance(a,b),count=Math.ceil(len/1.6),yaw=Math.atan2(b[0]-a[0],b[1]-a[1]);
  for(let i=0;i<count;i++) {
   const p=a.map((v,k)=>v+(b[k]-v)*(i+.5)/count);
   if(clear(...p,.1))box(target(...p),name,p[0],height(...p)+.02,p[1],width,.035,len/count-.02,yaw);
  }
 };
 pavement(...block.serviceLane.points,block.serviceLane.width,'CityCourtSurface');
 for(const [index,lot] of block.parcels.entries()) {
  pavement(lot.entrance,lot.gate,1.45);
  const [x,z]=lot.parking,c=target(x,z);
  if(clear(x,z,1.5)) {
   box(c,'CityCourtSurface',x,.018,z,3,.035,5.7);
   for(const dx of [-1.4,1.4])box(c,'CityMarkings',x+dx,.043,z,.05,.012,5.3);
   box(c,'CitySolid',x,.12,z+2.5,1.6,.23,.18);
  }
  const [sx,sz]=lot.shed,room=clear(sx,sz,1.7);
  if(room) {
   const c=target(sx,sz),color=index%2?[.29,.31,.28]:[.30,.24,.18];
   box(c,'CityEquipment',sx,1.05,sz,2.8,2.1,2.3,0,color);
   box(c,'CityMetal',sx,2.15,sz,3.05,.12,2.55);
   box(c,'CityWood',sx,.98,sz-1.17,1.35,1.9,.055);
   box(c,'CityMetal',sx+.45,1,sz-1.22,.04,.18,.05);
   for(let k=-4;k<=4;k++)box(c,'CityMetal',sx+k*.28,1.1,sz+1.16,.02,1.95,.025);
  }
  // Modest planting beds: sparse shrubs rather than another identical tree row.
  const bx=lot.yard[0],bz=lot.outline[0][1]+2.2;
  if(clear(bx,bz,1.3)) {
   box(target(bx,bz),'CityWood',bx,.04,bz,3,.07,1.35,0,[.18,.14,.10]);
   for(let k=0;k<3;k++) {
    const x=bx+(k-1)*.9,z=bz,c=target(x,z),cy=.45;
    const point=(theta,phi)=>[x+Math.sin(theta)*Math.cos(phi)*.58,cy+Math.cos(theta)*.45,z+Math.sin(theta)*Math.sin(phi)*.5];
    for(let a=0;a<6;a++)for(let b=0;b<10;b++) {
     const A=point(a/6*Math.PI,b/10*Math.PI*2),B=point((a+1)/6*Math.PI,b/10*Math.PI*2),C=point(a/6*Math.PI,(b+1)/10*Math.PI*2),D=point((a+1)/6*Math.PI,(b+1)/10*Math.PI*2);
     const color=[.12+(a%3)*.015,.22+(b%3)*.012,.10];
     tri(c,'CityShrubs',A,B,C,color);tri(c,'CityShrubs',B,D,C,color);
    }
   }
  }
 }
 // One screened waste corner off the public street; keep the lane unobstructed.
 const x=-34,z=30.2;
 if(clear(x,z,1.1)) {
  const c=target(x,z);box(c,'CityPaving',x,.025,z,4,.05,2.4);
  for(const dx of [-1.1,0,1.1]) {
   box(c,'CityEquipment',x+dx,.48,z,.8,.86,.8,0,[.16,.22,.18]);
   box(c,'CityMetal',x+dx,.94,z,.87,.08,.9);
   for(const side of [-1,1])box(c,'CityRubber',x+dx+side*.3,.13,z+.27,.12,.22,.12);
  }
  box(c,'CityWood',x,1,z+1.15,4,2,.08);
 }
}
