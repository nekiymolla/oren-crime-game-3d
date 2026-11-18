// Remove calibration-only geometry, never clamp real buildings into towers.
// node tools/assets/sanitize_world.mjs <chunksDir>
import {NodeIO} from '@gltf-transform/core';
import {ALL_EXTENSIONS} from '@gltf-transform/extensions';
import {getBounds, prune} from '@gltf-transform/functions';
import fs from 'node:fs';
import path from 'node:path';
const directory=process.argv[2];
if(!directory)throw new Error('Expected chunks directory');
const io=new NodeIO().registerExtensions(ALL_EXTENSIONS);
let removed=0;
for(const file of fs.readdirSync(directory).filter(f=>f.endsWith('.glb'))) {
  const doc=await io.read(path.join(directory,file));
  let count=0;
  for(const node of doc.getRoot().listNodes()) {
    if(!node.getMesh())continue;
    const {min,max}=getBounds(node);
    if(![...min,...max].every(Number.isFinite))throw new Error(`Invalid bounds: ${file}`);
    if(max[1]>1000 || min[1]<-1000) { node.dispose();count++; }
  }
  if(count) { await doc.transform(prune());await io.write(path.join(directory,file),doc);removed+=count; }
}
console.log(`Removed ${removed} calibration mesh nodes`);
