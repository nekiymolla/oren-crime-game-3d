// Prepare the CC0 camper and its native Walk/Run clips for Crime Oren.
// Additional gameplay poses are authored here for THIS rig; old Quaternius
// bone rotations are intentionally not copied onto an incompatible skeleton.
// node tools/assets/prepare_player.mjs <animated-source.glb> <output.glb>
import { NodeIO, Accessor, getBounds } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { dedup, prune, resample, weld } from '@gltf-transform/functions';
import { mat4, quat, vec3 } from 'gl-matrix';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const [input, output] = process.argv.slice(2);
if (!input || !output) throw new Error('Expected animated source and output GLB');
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(input), root = doc.getRoot(), buffer = root.listBuffers()[0];
const skin = root.listSkins()[0], joints = skin.listJoints();
const nodes = root.listNodes();
const byName = new Map(nodes.map(n => [n.getName(), n]));
if (joints.length !== 24 || !byName.has('RightForeArm')) throw new Error('Unexpected rig');
const native = new Map(root.listAnimations().map(a => [a.getName(), a]));
if (!native.has('Walk') || !native.has('Run')) throw new Error('Native locomotion clips required');
const original = new Map(nodes.map(n => [n, { t: n.getTranslation(), r: n.getRotation(), s: n.getScale() }]));
function reset() { for (const [n, p] of original) n.setTranslation(p.t).setRotation(p.r).setScale(p.s); }
function sample(animation, time) {
  reset();
  for (const channel of animation.listChannels()) {
    const sampler = channel.getSampler(), times = sampler.getInput().getArray(), values = sampler.getOutput();
    let i = 0;
    while (i + 1 < times.length && times[i + 1] < time) i++;
    const j = Math.min(i + 1, times.length - 1);
    const t = i === j ? 0 : Math.max(0, Math.min(1, (time - times[i]) / (times[j] - times[i])));
    const a = values.getElement(i, []), b = values.getElement(j, []);
    const node = channel.getTargetNode(), property = channel.getTargetPath();
    if (property === 'rotation') node.setRotation(quat.normalize([], quat.slerp([], a, b, t)));
    else if (property === 'translation') node.setTranslation(vec3.lerp([], a, b, t));
    else if (property === 'scale') node.setScale(vec3.lerp([], a, b, t));
  }
}
function capture() { return new Map(joints.map(n => [n.getName(), { t: n.getTranslation(), r: n.getRotation() }])); }
function apply(pose) {
  reset();
  for (const [name, p] of pose) byName.get(name).setTranslation(p.t).setRotation(p.r);
}
const duration = a => Math.max(...a.listSamplers().map(s => s.getInput().getMax([])[0]));
const frames = [];
for (let i = 0; i < 32; i++) { sample(native.get('Walk'), duration(native.get('Walk')) * i / 32); frames.push(capture()); }
const idle = new Map();
for (const joint of joints) {
  const name = joint.getName(), samples = frames.map(f => f.get(name));
  const reference = samples[0].r, rotation = [0, 0, 0, 0], translation = [0, 0, 0];
  for (const p of samples) {
    const sign = quat.dot(reference, p.r) < 0 ? -1 : 1;
    for (let k = 0; k < 4; k++) rotation[k] += p.r[k] * sign;
    for (let k = 0; k < 3; k++) translation[k] += p.t[k] / samples.length;
  }
  idle.set(name, { t: translation, r: quat.normalize([], rotation) });
}
idle.get('Hips').t[0] = original.get(byName.get('Hips')).t[0];
idle.get('Hips').t[2] = original.get(byName.get('Hips')).t[2];
const meshNode = nodes.find(n => n.getSkin());
const primitive = meshNode.getMesh().listPrimitives()[0];
const positions = primitive.getAttribute('POSITION'), weights = primitive.getAttribute('WEIGHTS_0'), jointIndices = primitive.getAttribute('JOINTS_0');
const inverseBinds = skin.getInverseBindMatrices();
function poseBounds() {
  const matrices = joints.map((n, i) => mat4.multiply([], n.getWorldMatrix(), inverseBinds.getElement(i, [])));
  const min = [Infinity, Infinity, Infinity], max = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < positions.getCount(); i++) {
    const point = positions.getElement(i, []), ids = jointIndices.getElement(i, []), w = weights.getElement(i, []), p = [0, 0, 0];
    for (let k = 0; k < 4; k++) {
      if (w[k] === 0) continue;
      const transformed = vec3.transformMat4([], point, matrices[ids[k]]);
      for (let axis = 0; axis < 3; axis++) p[axis] += transformed[axis] * w[k];
    }
    for (let k = 0; k < 3; k++) { min[k] = Math.min(min[k], p[k]); max[k] = Math.max(max[k], p[k]); }
  }
  return { min, max };
}
apply(idle);
// Skeleton translations are centimetres under Armature(scale=0.01), while
// the skinned surface is metres. Validate the DEFORMED surface, not getBounds.
idle.get('Hips').t[1] -= poseBounds().min[1] * 100;
const worldPosition = n => mat4.getTranslation([], n.getWorldMatrix());
const worldRotation = n => quat.normalize([], mat4.getRotation([], n.getWorldMatrix()));
function setWorldRotation(node, q) {
  const parent = node.getParentNode();
  node.setRotation(quat.normalize([], quat.multiply([], parent ? quat.invert([], worldRotation(parent)) : quat.create(), q)));
}
function pointBone(node, child, direction) {
  const from = vec3.normalize([], vec3.subtract([], worldPosition(child), worldPosition(node)));
  const to = vec3.normalize([], direction);
  setWorldRotation(node, quat.multiply([], quat.rotationTo([], from, to), worldRotation(node)));
}
function aimArm(side, goal, hint) {
  const arm = byName.get(side + 'Arm'), elbow = byName.get(side + 'ForeArm'), hand = byName.get(side + 'Hand');
  const s = worldPosition(arm), e = worldPosition(elbow), w = worldPosition(hand);
  const l1 = vec3.distance(s, e), l2 = vec3.distance(e, w);
  const axis = vec3.normalize([], vec3.subtract([], goal, s));
  const distance = Math.max(Math.abs(l1 - l2) + 0.01, Math.min(l1 + l2 - 0.01, vec3.distance(s, goal)));
  const wrist = vec3.scaleAndAdd([], s, axis, distance);
  const bend = vec3.subtract([], hint, s);
  vec3.scaleAndAdd(bend, bend, axis, -vec3.dot(bend, axis)); vec3.normalize(bend, bend);
  const along = (l1 * l1 - l2 * l2 + distance * distance) / (2 * distance);
  const elbowGoal = vec3.scaleAndAdd([], vec3.scaleAndAdd([], s, axis, along), bend, Math.sqrt(Math.max(0, l1 * l1 - along * along)));
  pointBone(arm, elbow, vec3.subtract([], elbowGoal, s));
  pointBone(elbow, hand, vec3.subtract([], wrist, worldPosition(elbow)));
  const handDirection = vec3.transformQuat([], [0, 1, 0], worldRotation(hand));
  setWorldRotation(hand, quat.multiply([], quat.rotationTo([], handDirection, [0, 0, 1]), worldRotation(hand)));
}
apply(idle);
aimArm('Right', [-0.14, 1.29, 0.43], [-0.42, 1.07, 0.16]);
aimArm('Left', [0.08, 1.26, 0.36], [0.4, 1.03, 0.12]);
const aim = capture();
const appendRotation = (name, axis, angle) => {
  const node = byName.get(name); node.setRotation(quat.normalize([], quat.multiply([], node.getRotation(), quat.setAxisAngle([], axis, angle))));
};
function bake(name, seconds, poseAt) {
  const animation = doc.createAnimation(name), count = Math.ceil(seconds * 30) + 1;
  const time = doc.createAccessor().setType(Accessor.Type.SCALAR).setArray(Float32Array.from({ length: count }, (_, i) => seconds * i / (count - 1))).setBuffer(buffer);
  const data = new Map(joints.map(n => [n, { t: [], r: [] }]));
  for (let i = 0; i < count; i++) {
    poseAt(seconds * i / (count - 1));
    for (const [node, values] of data) { values.t.push(...node.getTranslation()); values.r.push(...node.getRotation()); }
  }
  for (const [node, values] of data) {
    for (const [property, array, type] of [['translation', values.t, 'VEC3'], ['rotation', values.r, 'VEC4']]) {
      const output = doc.createAccessor().setType(type).setArray(new Float32Array(array)).setBuffer(buffer);
      const sampler = doc.createAnimationSampler().setInput(time).setOutput(output).setInterpolation('LINEAR');
      animation.addSampler(sampler).addChannel(doc.createAnimationChannel().setTargetNode(node).setTargetPath(property).setSampler(sampler));
    }
  }
  return animation;
}
bake('Idle', 2, t => { apply(idle); appendRotation('Spine', [1, 0, 0], Math.sin(t * Math.PI) * 0.008); });
bake('Idle_Gun_Pointing', 2, t => { apply(aim); appendRotation('Spine', [1, 0, 0], Math.sin(t * Math.PI) * 0.004); });
bake('Gun_Shoot', 0.3, t => { apply(aim); const kick = Math.sin(Math.PI * t / 0.3); appendRotation('RightArm', [1, 0, 0], -0.08 * kick); appendRotation('LeftArm', [1, 0, 0], -0.035 * kick); });
bake('HitRecieve', 0.5, t => { apply(idle); appendRotation('Spine', [1, 0, 0], -0.18 * Math.sin(Math.PI * t / 0.5)); });
bake('Interact', 1.2, t => {
  apply(idle); const reach = Math.sin(Math.PI * t / 1.2);
  aimArm('Right', [-0.24, 1.0, 0.1 + reach * 0.33], [-0.45, 1.0, 0.12]);
});
const arms = joints.filter(n => /^(Left|Right)(Shoulder|Arm|ForeArm|Hand)$/.test(n.getName()));
bake('Run_Shoot', duration(native.get('Run')), t => {
  sample(native.get('Run'), t);
  for (const n of arms) n.setRotation(aim.get(n.getName()).r);
});
bake('Death', 1.05, t => {
  apply(idle); const progress = Math.min(1, t / 0.85), ease = progress * progress * (3 - 2 * progress);
  const hips = byName.get('Hips'), p = hips.getTranslation();
  p[1] += (22 - p[1]) * ease; hips.setTranslation(p);
  appendRotation('Hips', [1, 0, 0], -Math.PI / 2 * ease);
});
// Keep the model's default pose in a neutral stance as well.
apply(idle);
for (const material of root.listMaterials()) material.setMetallicFactor(0).setRoughnessFactor(0.85).setDoubleSided(false);
// Preserve the face texture while limiting its GPU footprint to 2048 px.
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'crime-player-'));
try {
  for (const [i, texture] of root.listTextures().entries()) {
    const source = path.join(temporary, `${i}.source`), target = path.join(temporary, `${i}.jpg`);
    fs.writeFileSync(source, texture.getImage());
    execFileSync('python3', ['-c', `
from PIL import Image
import sys
im = Image.open(sys.argv[1]).convert('RGB')
im.thumbnail((2048,2048), Image.Resampling.LANCZOS)
im.save(sys.argv[2], 'JPEG', quality=92, optimize=True)
`, source, target]);
    texture.setImage(fs.readFileSync(target)).setMimeType('image/jpeg');
  }
} finally { fs.rmSync(temporary, { recursive: true }); }
const checks = {};
for (const name of ['Idle', 'Walk', 'Run', 'Idle_Gun_Pointing', 'Gun_Shoot', 'Death']) {
  const animation = root.listAnimations().find(a => a.getName() === name);
  sample(animation, name === 'Death' ? duration(animation) : duration(animation) / 2);
  checks[name] = poseBounds();
}
apply(idle);
// Normalize the authored centimetre rig to metres. Without this step the
// skin renders correctly but ordinary mesh bounds are 100x too small.
for (const joint of joints) joint.setTranslation(joint.getTranslation().map(v => v * 0.01));
byName.get('Armature').setScale([1, 1, 1]);
const convertedTranslations = new Set();
for (const animation of root.listAnimations()) {
  for (const channel of animation.listChannels()) {
    if (channel.getTargetPath() !== 'translation') continue;
    const accessor = channel.getSampler().getOutput();
    if (convertedTranslations.has(accessor)) continue;
    convertedTranslations.add(accessor);
    accessor.setArray(Float32Array.from(accessor.getArray(), v => v * 0.01));
  }
}
const bindValues = inverseBinds.getArray().slice();
for (let i = 0; i < bindValues.length; i++) if (i % 16 !== 15) bindValues[i] *= 0.01;
inverseBinds.setArray(bindValues);
const normalizedIdle = poseBounds();
for (let axis = 0; axis < 3; axis++) {
  if (Math.abs(normalizedIdle.min[axis] - checks.Idle.min[axis]) > 0.002 || Math.abs(normalizedIdle.max[axis] - checks.Idle.max[axis]) > 0.002) throw new Error('Unit conversion changed the deformed surface');
}
const normalizedBounds = getBounds(root.listScenes()[0]);
if (normalizedBounds.max[1] < 1.65 || normalizedBounds.max[1] > 1.9) throw new Error('Normalized character bounds are invalid');
await doc.transform(weld(), dedup(), resample(), prune());
await io.write(output, doc);
const summary = {
  source: 'https://vibeassets.io/a/zpepqtthci', license: 'CC0-1.0',
  sourceSha256: createHash('sha256').update(fs.readFileSync(input)).digest('hex'),
  joints: joints.length, triangles: 31122, checks, normalizedBounds,
  nativeClips: ['Walk', 'Run'], authoredClips: ['Idle', 'Idle_Gun_Pointing', 'Gun_Shoot', 'HitRecieve', 'Interact', 'Run_Shoot', 'Death'],
};
fs.writeFileSync(output.replace(/\.glb$/, '.json'), JSON.stringify(summary, null, 2) + '\n');
console.log(JSON.stringify(summary, null, 2));
