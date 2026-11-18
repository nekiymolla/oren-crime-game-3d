// Prepare Grab3D's CC0 1980s Sedan for Crime Oren. Requires Python/Pillow
// to read the lamp atlas and resize PBR textures to a mobile 1024px budget.
// node tools/assets/prepare_classic_sedan.mjs <source.glb> <output.glb>
import { NodeIO, getBounds } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { transformMesh, weld, dedup, prune } from '@gltf-transform/functions';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const [input, output] = process.argv.slice(2);
if (!input || !output) throw new Error('Expected source.glb and output.glb');
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(input);
const root = doc.getRoot();
const buffer = root.listBuffers()[0];
const sources = root.listNodes().filter(n => n.getMesh());
if (sources.length !== 6) throw new Error('Unexpected source layout; review before adapting');
const flip = [-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1];
for (const node of sources) {
  transformMesh(node.getMesh(), node.getWorldMatrix());
  transformMesh(node.getMesh(), flip);
}
for (const node of sources) node.setTranslation([0, 0, 0]).setRotation([0, 0, 0, 1]).setScale([1, 1, 1]);
const bodySource = sources.find(n => n.getName() === '1980s-sedan_body');
const glassSource = sources.find(n => n.getName() === '1980s-sedan_windows');
const bodyPrimitive = bodySource.getMesh().listPrimitives()[0];
const bodyMaterial = bodyPrimitive.getMaterial().setName('BodyTextured');
bodyMaterial.setDoubleSided(false);
const positions = bodyPrimitive.getAttribute('POSITION');
const uvs = bodyPrimitive.getAttribute('TEXCOORD_0');
const indices = Array.from(bodyPrimitive.getIndices().getArray());
const bounds = getBounds(bodySource);
const samples = [];
for (let i = 0; i < indices.length; i += 3) {
  const p = [0, 0, 0], uv = [0, 0];
  for (let j = 0; j < 3; j++) {
    const v = positions.getElement(indices[i + j], []);
    const t = uvs.getElement(indices[i + j], []);
    for (let k = 0; k < 3; k++) p[k] += v[k] / 3;
    uv[0] += t[0] / 3; uv[1] += t[1] / 3;
  }
  samples.push({ uv, front: p[2] < bounds.min[2] + 0.35, rear: p[2] > bounds.max[2] - 0.35 });
}
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'crime-sedan-'));
let labels;
try {
  fs.writeFileSync(path.join(temporary, 'atlas.jpg'), bodyMaterial.getBaseColorTexture().getImage());
  fs.writeFileSync(path.join(temporary, 'samples.json'), JSON.stringify(samples));
  labels = JSON.parse(execFileSync('python3', ['-c', `
import json, sys
from PIL import Image
image = Image.open(sys.argv[1]).convert('RGB')
labels = []
for face in json.load(open(sys.argv[2])):
    u,v = face['uv']
    r,g,b = [c/255 for c in image.getpixel((max(0,min(image.width-1,int(u*image.width))),max(0,min(image.height-1,int(v*image.height)))))]
    labels.append('front' if face['front'] and r>.55 and g>.35 and b<.45 else 'rear' if face['rear'] and r>.45 and r>g*1.35 and r>b*1.35 else 'body')
print(json.dumps(labels))
`, path.join(temporary, 'atlas.jpg'), path.join(temporary, 'samples.json')], { encoding: 'utf8' }));
} finally { fs.rmSync(temporary, { recursive: true }); }
// Assign whole connected lamp surfaces, not isolated UV-sampled triangles.
// Otherwise atlas boundary filtering leaves a checkerboard of emissive faces.
const parent = Array.from({ length: positions.getCount() }, (_, i) => i);
function find(i) { while (parent[i] !== i) { parent[i] = parent[parent[i]]; i = parent[i]; } return i; }
function unite(a, b) { parent[find(a)] = find(b); }
const vertexKeys = new Map();
for (let i = 0; i < positions.getCount(); i++) {
  const key = positions.getElement(i, []).map(x => Math.round(x * 1e5)).join(',');
  if (vertexKeys.has(key)) unite(i, vertexKeys.get(key)); else vertexKeys.set(key, i);
}
for (let i = 0; i < indices.length; i += 3) {
  unite(indices[i], indices[i + 1]); unite(indices[i + 1], indices[i + 2]);
}
const components = new Map();
for (let i = 0; i < labels.length; i++) {
  const key = find(indices[i * 3]);
  const component = components.get(key) ?? { total: 0, front: 0, rear: 0 };
  component.total++;
  if (labels[i] !== 'body') component[labels[i]]++;
  components.set(key, component);
}
labels = labels.map((_, i) => {
  const c = components.get(find(indices[i * 3]));
  if (c.total > 600) return 'body';
  if (c.front / c.total > 0.1) return 'front';
  if (c.rear / c.total > 0.1) return 'rear';
  return 'body';
});
// Bound the embedded image footprint before the engine generates mipmaps.
// This is numeric resampling of the supplied maps; no new image content.
const resizeDir = fs.mkdtempSync(path.join(os.tmpdir(), 'crime-sedan-textures-'));
try {
  for (const [index, texture] of root.listTextures().entries()) {
    const source = path.join(resizeDir, `${index}.source`);
    const target = path.join(resizeDir, `${index}.png`);
    fs.writeFileSync(source, texture.getImage());
    const resized = execFileSync('python3', ['-c', `
from PIL import Image
import sys
im = Image.open(sys.argv[1])
if max(im.size) > 1024:
    ratio = 1024 / max(im.size)
    im = im.resize((round(im.width * ratio), round(im.height * ratio)), Image.Resampling.LANCZOS)
    im.save(sys.argv[2], format='PNG', optimize=True)
    print('yes')
`, source, target], { encoding: 'utf8' }).trim();
    if (resized === 'yes') texture.setImage(fs.readFileSync(target)).setMimeType('image/png');
  }
} finally { fs.rmSync(resizeDir, { recursive: true }); }
const groups = { body: [], front: [], rear: [] };
for (let i = 0; i < labels.length; i++) groups[labels[i]].push(...indices.slice(i * 3, i * 3 + 3));
if (!groups.front.length || !groups.rear.length) throw new Error('Lamp face classification failed');
const bodyMesh = doc.createMesh('Body');
for (const [kind, group] of Object.entries(groups)) {
  const primitive = bodyPrimitive.clone();
  primitive.setIndices(doc.createAccessor().setType('SCALAR').setArray(new Uint32Array(group)).setBuffer(buffer));
  if (kind !== 'body') {
    primitive.setMaterial(doc.createMaterial(kind === 'front' ? 'Headlights' : 'TailLights')
      .setBaseColorFactor(kind === 'front' ? [0.8, 0.78, 0.65, 1] : [0.6, 0.02, 0.01, 1])
      .setRoughnessFactor(0.25));
  }
  bodyMesh.addPrimitive(primitive);
}
for (const p of glassSource.getMesh().listPrimitives()) {
  p.getMaterial().setName('ClearGlass').setRoughnessFactor(0.12);
  bodyMesh.addPrimitive(p);
}
for (const m of root.listMaterials()) {
  if (m.getName().includes('_tire_x')) m.setName('Tire');
  if (m.getName().includes('_rim_x')) m.setName('Rim');
  if (m.getName().includes('_hubcap_x')) m.setName('Hubcap');
  if (m.getName().includes('_trim_charcoal_x')) m.setName('Trim');
}
const wheels = [];
for (const node of sources.filter(n => n.getName().includes('_wheel_'))) {
  const box = getBounds(node);
  const center = box.min.map((v, i) => (v + box.max[i]) / 2);
  const front = center[2] < 0;
  const role = `Wheel_${front ? 'F' : 'R'}${center[0] > 0 ? 'L' : 'R'}`;
  const translate = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -center[0], -center[1], -center[2], 1];
  transformMesh(node.getMesh(), translate);
  wheels.push({ role, mesh: node.getMesh(), center, radius: (box.max[1] - box.min[1]) / 2 });
}
for (const scene of root.listScenes()) scene.dispose();
const scene = doc.createScene('Classic sedan');
scene.addChild(doc.createNode('Body').setMesh(bodyMesh));
for (const wheel of wheels) scene.addChild(doc.createNode(wheel.role).setMesh(wheel.mesh).setTranslation(wheel.center));
root.setDefaultScene(scene);
for (const node of sources) node.dispose();
await doc.transform(weld(), dedup(), prune());
await io.write(output, doc);
const finalBounds = getBounds(scene);
const summary = {
  source: 'https://grab3d.com/models/vehicles/1980s-sedan/', license: 'CC0-1.0',
  sourceSha256: createHash('sha256').update(fs.readFileSync(input)).digest('hex'),
  maxTextureSize: 1024,
  width: finalBounds.max[0] - finalBounds.min[0], height: finalBounds.max[1] - finalBounds.min[1],
  length: finalBounds.max[2] - finalBounds.min[2], wheelRadius: wheels[0].radius,
  wheelbase: Math.abs(wheels.find(w => w.role === 'Wheel_FL').center[2] - wheels.find(w => w.role === 'Wheel_RL').center[2]),
  wheels: wheels.map(w => ({ name: w.role, centerGame: [w.center[0], w.center[1], -w.center[2]] })),
  frontLampTriangles: groups.front.length / 3, rearLampTriangles: groups.rear.length / 3,
};
fs.writeFileSync(output.replace(/\.glb$/, '.json'), JSON.stringify(summary, null, 2) + '\n');
console.log(summary);
