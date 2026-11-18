// Authored details constrained to mapped footprints. All returned objects are
// approximate: the footprint is evidence for a place, not for its equipment.
export function projectToSegment(p,a,b) {
  const dx=b[0]-a[0],dz=b[1]-a[1],d=dx*dx+dz*dz;
  const t=d?Math.max(0,Math.min(1,((p[0]-a[0])*dx+(p[1]-a[1])*dz)/d)):0;
  return [a[0]+dx*t,a[1]+dz*t];
}
export const distance=(a,b)=>Math.hypot(a[0]-b[0],a[1]-b[1]);
export function inside(p,points) {
  let hit=false;
  for(let i=0,j=points.length-1;i<points.length;j=i++) {
    const a=points[i],b=points[j];
    if((a[1]>p[1])!==(b[1]>p[1])&&p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0])hit=!hit;
  }
  return hit;
}
export function nearestPath(p,paths) {
  let best={distance:Infinity,point:p,width:2};
  for(const path of paths)for(let i=1;i<path.points.length;i++) {
    const point=projectToSegment(p,path.points[i-1],path.points[i]),d=distance(p,point);
    if(d<best.distance)best={distance:d,point,width:path.width,basis:path.osm};
  }
  return best;
}
export function planAreas(map,{clear=()=>true,height=()=>0}={}) {
  const fences=[],equipment=[];
  for(const area of map.areas) {
    const outline=area.points.slice(0,-1),center=area.center;
    const frameEdge=outline.map((a,i)=>[a,outline[(i+1)%outline.length]]).sort((a,b)=>distance(...b)-distance(...a))[0];
    const len=distance(...frameEdge),u=[(frameEdge[1][0]-frameEdge[0][0])/len,(frameEdge[1][1]-frameEdge[0][1])/len],v=[-u[1],u[0]];
    const point=(across,along)=>[center[0]+v[0]*across+u[0]*along,center[1]+v[1]*across+u[1]*along];
    function add(kind,across,along,width,length) {
      const p=point(across,along),corners=[[-1,-1],[-1,1],[1,-1],[1,1]].map(([a,b])=>[p[0]+v[0]*a*(width/2+.6)+u[0]*b*(length/2+.6),p[1]+v[1]*a*(width/2+.6)+u[1]*b*(length/2+.6)]);
      if(!corners.every(c=>inside(c,outline)&&clear(...c)))return;
      equipment.push({kind,point:p,y:height(...p),yaw:Math.atan2(u[0],u[1]),width,length,placement:'inferred',basis:area.osm,reason:'Authored equipment inside mapped leisure footprint; exact real layout unverified'});
    }
    if(area.tags.leisure==='fitness_station') {add('parallel_bars',0,0,1.4,2.2);continue;}
    if(area.tags.leisure==='playground') {add('swings',0,6,4.5,3.6);add('slide',0,-6,2.5,5);}
    else if(area.tags.sport==='skateboard') {add('skate_bank',0,-8,4,4);add('skate_bank',0,8,4,4);add('grind_rail',0,0,.7,3);}
    else if(area.tags.leisure==='pitch')add('court',0,0,10,20);
    else continue;
    // Inset the perimeter slightly. Pick a wide entrance facing a real path.
    const ring=outline.map(p=>{const d=distance(p,center);return [p[0]+(center[0]-p[0])*.45/d,p[1]+(center[1]-p[1])*.45/d];});
    let gate;
    for(let i=0;i<ring.length;i++) {
      const a=ring[i],b=ring[(i+1)%ring.length],length=distance(a,b);
      if(length<4.2)continue;
      const steps=Math.ceil(length/1);
      for(let j=0;j<=steps;j++) {
        const t=Math.max(1.9/length,Math.min(1-1.9/length,j/steps));
        const p=[a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t],path=nearestPath(p,map.paths);
        if(clear(...p)&&(!gate||path.distance<gate.distance))gate={point:p,path: path.point,distance:path.distance,edge:i,width:3.6};
      }
    }
    if(!gate)continue;
    const sections=[];
    for(let i=0;i<ring.length;i++) {
      const a=ring[i],b=ring[(i+1)%ring.length],length=distance(a,b),count=Math.ceil(length/.35);
      let first;
      const at=t=>[a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t];
      for(let j=0;j<count;j++) {
        const p=at((j+.5)/count),route=nearestPath(p,map.paths);
        const open=(i===gate.edge&&distance(p,gate.point)<gate.width/2+.35)||route.distance<route.width/2+.85||!clear(...p);
        if(!open&&first===undefined)first=j;
        if(first!==undefined&&(open||j===count-1)) {
          const end=open?j:j+1;
          if((end-first)*length/count>.7)sections.push({a:at(first/count),b:at(end/count),y:height(...at((first+end)/2/count))});
          first=undefined;
        }
      }
    }
    fences.push({placement:'inferred',basis:area.osm,reason:'Authored railing following mapped leisure footprint; real fence unverified',height:area.tags.leisure==='playground'?1.05:1.6,thickness:.08,gate,sections});
  }
  return {fences,equipment};
}
