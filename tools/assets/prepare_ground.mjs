// Упаковывает текстуры земли (ambientCG, CC0) в крошечный glb-контейнер:
// игра грузит его loadScene и берёт из материалов Grass и Dirt текстуры для
// шейдера земли (assets/shaders/ground.fmat). Отдельный загрузчик текстур
// (.fstex) требовал бы ещё одной настройки сборочного хука — а glb движок
// уже умеет.
//
// Использование: node tools/assets/prepare_ground.mjs <Grass004_Color.jpg> <Ground037_Color.jpg> <out.glb>
import { Document, NodeIO } from '@gltf-transform/core';
import fs from 'node:fs';

const [grassPath, dirtPath, out] = process.argv.slice(2);
const doc = new Document();
const buffer = doc.createBuffer();
const scene = doc.createScene('Ground');

const positions = new Float32Array([0, 0, 0, 1, 0, 0, 0, 0, 1]);
const uvs = new Float32Array([0, 0, 1, 0, 0, 1]);
const normals = new Float32Array([0, 1, 0, 0, 1, 0, 0, 1, 0]);

for (const [name, file] of [['Grass', grassPath], ['Dirt', dirtPath]]) {
  const texture = doc.createTexture(name).setImage(fs.readFileSync(file)).setMimeType('image/jpeg');
  const material = doc.createMaterial(name).setBaseColorTexture(texture).setRoughnessFactor(1).setMetallicFactor(0);
  const prim = doc
    .createPrimitive()
    .setMaterial(material)
    .setAttribute('POSITION', doc.createAccessor().setType('VEC3').setArray(positions).setBuffer(buffer))
    .setAttribute('NORMAL', doc.createAccessor().setType('VEC3').setArray(normals).setBuffer(buffer))
    .setAttribute('TEXCOORD_0', doc.createAccessor().setType('VEC2').setArray(uvs).setBuffer(buffer));
  scene.addChild(doc.createNode(name).setMesh(doc.createMesh(name).addPrimitive(prim)));
}

await new NodeIO().write(out, doc);
console.log(`${out}: ${(fs.statSync(out).size / 1024).toFixed(0)} KB`);
