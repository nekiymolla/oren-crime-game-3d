// Готовит персонажей Quaternius (Ultimate Modular Men/Women, CC0) к игре.
//
// В исходниках персонаж — 4-5 скинованных мешей по 1-6 материалов (плоские
// цвета без текстур), т.е. 10-14 draw call'ов на человека. На толпу из ~25
// это сотни вызовов плюс столько же в тени. Здесь:
//   * цвет каждого материала запекается в COLOR_0 вершин (шейдер flutter_scene
//     умножает base color на цвет вершины), все части получают один общий
//     материал и склеиваются в ОДИН примитив — 1 draw call на персонажа;
//   * лишние атрибуты (UV — текстур всё равно нет) выкидываются;
//   * анимации: у всех персонажей один и тот же скелет (62 кости с
//     одинаковыми именами), а клипы flutter_scene привязываются к костям по
//     имени — поэтому анимации храним только в двух "носителях" (мужском и
//     женском, у них разная высота таза в translation-каналах), у остальных
//     вырезаем. Оставляем только нужные игре клипы, имена без префикса
//     "CharacterArmature|".
//
// Использование: node tools/assets/prepare_characters.mjs <папка мужчин> <папка женщин> <выходная папка>
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { dedup, joinPrimitives, prune, resample, weld } from '@gltf-transform/functions';
import fs from 'node:fs';
import path from 'node:path';

const [menDir, womenDir, outDir] = process.argv.slice(2);

// Клипы, которые использует игра (lib/characters/character_model.dart).
const KEEP_ANIMS = new Set([
  'Idle', 'Idle_Neutral', 'Walk', 'Run', 'Death', 'HitRecieve',
  'Gun_Shoot', 'Idle_Gun', 'Idle_Gun_Pointing', 'Run_Shoot', 'Interact', 'Wave', 'Punch_Right',
]);

// id в игре -> исходник. carriesAnims — файл-носитель анимаций своего пола.
const CHARACTERS = [
  { id: 'male_casual', src: [menDir, 'Casual_Character.glb'], carriesAnims: true },
  { id: 'male_hoodie', src: [menDir, 'Hoodie_Character.glb'] },
  { id: 'male_business', src: [menDir, 'Business_Man.glb'] },
  { id: 'male_punk', src: [menDir, 'Punk.glb'] },
  { id: 'male_worker', src: [menDir, 'Worker.glb'] },
  { id: 'male_farmer', src: [menDir, 'Farmer.glb'] },
  { id: 'male_adventurer', src: [menDir, 'Adventurer.glb'] },
  { id: 'male_swat', src: [menDir, 'SWAT.glb'] },
  { id: 'female_casual', src: [womenDir, 'Animated_Woman.glb'], carriesAnims: true },
  { id: 'female_casual2', src: [womenDir, 'Animated_Woman_qJ2gsTUBHL.glb'] },
  { id: 'female_adventurer', src: [womenDir, 'Adventurer.glb'] },
  { id: 'female_punk', src: [womenDir, 'Punk.glb'] },
  { id: 'female_suit', src: [womenDir, 'Suit.glb'] },
  { id: 'female_worker', src: [womenDir, 'Worker.glb'] },
  { id: 'female_soldier', src: [womenDir, 'Soldier.glb'] },
];

const KEEP_ATTRIBUTES = new Set(['POSITION', 'NORMAL', 'JOINTS_0', 'WEIGHTS_0', 'COLOR_0']);

/** Запекает материалы в цвета вершин и склеивает все скинованные части в один примитив. */
function bakeAndMerge(doc) {
  const root = doc.getRoot();
  const buffer = root.listBuffers()[0];
  const meshNodes = root.listNodes().filter((n) => n.getMesh());
  // Нескинованные меши (пристёгнутые к костям мелочи) у выбранных
  // персонажей не встречаются — выбрасываем на всякий случай.
  for (const node of meshNodes.filter((n) => !n.getSkin())) node.dispose();
  const skinned = meshNodes.filter((n) => n.getSkin());
  const target = skinned[0];
  // Трансформации самих меш-узлов у частей разные, но для скинованного меша
  // glTF их игнорирует (положение задают кости) — склеивать можно как есть.

  const material = doc
    .createMaterial('Character')
    .setBaseColorFactor([1, 1, 1, 1])
    .setRoughnessFactor(0.8)
    .setMetallicFactor(0);

  const prims = [];
  for (const node of skinned) {
    for (const prim of node.getMesh().listPrimitives()) {
      const color = prim.getMaterial()?.getBaseColorFactor() ?? [1, 1, 1, 1];
      const count = prim.getAttribute('POSITION').getCount();
      const colors = new Float32Array(count * 4);
      for (let i = 0; i < count; i++) colors.set([color[0], color[1], color[2], 1], i * 4);
      prim.setAttribute('COLOR_0', doc.createAccessor().setType('VEC4').setArray(colors).setBuffer(buffer));
      for (const semantic of prim.listSemantics()) {
        if (!KEEP_ATTRIBUTES.has(semantic)) prim.setAttribute(semantic, null);
      }
      // joinPrimitives требует одинаковых типов компонент у всех частей.
      const joints = prim.getAttribute('JOINTS_0');
      if (!(joints.getArray() instanceof Uint16Array)) {
        prim.setAttribute('JOINTS_0', doc.createAccessor().setType('VEC4').setArray(Uint16Array.from(joints.getArray())).setBuffer(buffer));
      }
      const indices = prim.getIndices();
      if (!(indices.getArray() instanceof Uint32Array)) {
        prim.setIndices(doc.createAccessor().setType('SCALAR').setArray(Uint32Array.from(indices.getArray())).setBuffer(buffer));
      }
      prim.setMaterial(material);
      prims.push(prim);
    }
  }

  const joined = joinPrimitives(prims);
  const mesh = doc.createMesh('Body').addPrimitive(joined);
  target.setMesh(mesh).setName('Body_Mesh');
  for (const node of skinned.slice(1)) node.dispose();
}

function filterAnimations(doc, keep) {
  for (const animation of doc.getRoot().listAnimations()) {
    const name = animation.getName().replace(/^.*\|/, '');
    if (keep && KEEP_ANIMS.has(name)) {
      animation.setName(name);
    } else {
      animation.dispose();
    }
  }
}

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
fs.mkdirSync(outDir, { recursive: true });
for (const character of CHARACTERS) {
  const doc = await io.read(path.join(...character.src));
  bakeAndMerge(doc);
  filterAnimations(doc, character.carriesAnims === true);
  await doc.transform(weld(), resample(), dedup(), prune());
  const out = path.join(outDir, `${character.id}.glb`);
  await io.write(out, doc);
  const root = doc.getRoot();
  const tris = root.listMeshes().reduce((s, m) => s + m.listPrimitives().reduce((t, p) => t + p.getIndices().getCount() / 3, 0), 0);
  console.log(`${out}: ${(fs.statSync(out).size / 1024).toFixed(0)} KB, tris=${tris}, prims=${root.listMeshes().reduce((s, m) => s + m.listPrimitives().length, 0)}, anims=${root.listAnimations().length}`);
}
