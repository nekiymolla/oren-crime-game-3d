// Готовит машины Quaternius (Cars Bundle, CC0) к игре.
//
// В исходниках кузов — один меш (примитив на материал), колёса — отдельные
// меши, но с опорной точкой в центре машины: крутить их нельзя. Здесь:
//   * колёса перецентрируются: вершины сдвигаются к центру колеса, узел
//     ставится в этот центр (задние колёса — одна ось, крутятся вместе);
//   * узлы получают постоянные имена Body / Wheel_FL / Wheel_FR / Wheels_R,
//     материалы — роли Paint / Glass / Headlights / TailLights / Siren_*:
//     игра перекрашивает кузов и включает фары по именам;
//   * модель разворачивается так, чтобы перед машины после импорта в
//     flutter_scene (он переворачивает Z) смотрел на +Z игры: в glTF фары
//     должны быть на -Z.
//
// Использование: node tools/assets/prepare_vehicles.mjs <папка бандла> <выходная папка>
import { NodeIO, getBounds } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { dedup, prune, weld } from '@gltf-transform/functions';
import fs from 'node:fs';
import path from 'node:path';

const [srcDir, outDir] = process.argv.slice(2);

// paint — материалы кузова, которые игра перекрашивает (пусто — цвет
// фирменный: такси, полиция).
const VEHICLES = [
  { id: 'sedan', src: 'Car.glb', paint: ['Blue'] },
  { id: 'hatchback', src: 'Car_unqqkULtRU.glb', paint: ['LightBlue'] },
  { id: 'suv', src: 'SUV.glb', paint: ['White'] },
  { id: 'sports', src: 'Sports_Car.glb', paint: ['White'] },
  { id: 'sports2', src: 'Sports_Car_OyqKvX9xNh.glb', paint: ['Orange'] },
  { id: 'taxi', src: 'Taxi.glb', paint: [] },
  { id: 'police', src: 'Police_Car.glb', paint: [] },
];

const ROLE_BY_MATERIAL = {
  Windows: 'Glass',
  Headlights: 'Headlights',
  TailLights: 'TailLights',
  WhiteLights: 'Siren_White',
  BlueLights: 'Siren_Blue',
};

function wheelRole(name) {
  if (/FrontLeftWheel/.test(name)) return 'Wheel_FL';
  if (/FrontRightWheel/.test(name)) return 'Wheel_FR';
  if (/BackWheels/.test(name)) return 'Wheels_R';
  return null;
}

/** Повернуть все вершины узла на 180° вокруг Y (x,z -> -x,-z). */
function rotateMeshY180(mesh) {
  for (const prim of mesh.listPrimitives()) {
    for (const semantic of ['POSITION', 'NORMAL']) {
      const accessor = prim.getAttribute(semantic);
      if (!accessor) continue;
      const a = accessor.getArray().slice();
      for (let i = 0; i < a.length; i += 3) {
        a[i] = -a[i];
        a[i + 2] = -a[i + 2];
      }
      accessor.setArray(a);
    }
    const tangent = prim.getAttribute('TANGENT');
    if (tangent) {
      const a = tangent.getArray().slice();
      for (let i = 0; i < a.length; i += 4) {
        a[i] = -a[i];
        a[i + 2] = -a[i + 2];
      }
      tangent.setArray(a);
    }
  }
}

function translateMesh(mesh, offset) {
  for (const prim of mesh.listPrimitives()) {
    const accessor = prim.getAttribute('POSITION');
    const a = accessor.getArray().slice();
    for (let i = 0; i < a.length; i += 3) {
      a[i] -= offset[0];
      a[i + 1] -= offset[1];
      a[i + 2] -= offset[2];
    }
    accessor.setArray(a);
  }
}

function centroidZ(doc, materialName) {
  let sum = 0;
  let count = 0;
  for (const mesh of doc.getRoot().listMeshes()) {
    for (const prim of mesh.listPrimitives()) {
      if (prim.getMaterial()?.getName() !== materialName) continue;
      const a = prim.getAttribute('POSITION').getArray();
      for (let i = 2; i < a.length; i += 3) {
        sum += a[i];
        count++;
      }
    }
  }
  return count ? sum / count : 0;
}

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
fs.mkdirSync(outDir, { recursive: true });
const summary = {};
for (const vehicle of VEHICLES) {
  const doc = await io.read(path.join(srcDir, vehicle.src));
  const root = doc.getRoot();
  const meshNodes = root.listNodes().filter((n) => n.getMesh());
  for (const node of meshNodes) {
    const t = node.getTranslation();
    const r = node.getRotation();
    const s = node.getScale();
    if (t.some((v) => Math.abs(v) > 1e-6) || Math.abs(r[3] - 1) > 1e-6 || s.some((v) => Math.abs(v - 1) > 1e-6)) {
      throw new Error(`${vehicle.src}: ${node.getName()} с трансформацией — скрипт рассчитан на единичную`);
    }
  }

  // Фары в glTF должны быть на -Z (после переворота Z импортёром — +Z игры).
  const flip = centroidZ(doc, 'Headlights') > 0;
  if (flip) for (const node of meshNodes) rotateMeshY180(node.getMesh());

  for (const material of root.listMaterials()) {
    const name = material.getName();
    if (vehicle.paint.includes(name)) material.setName('Paint');
    else if (ROLE_BY_MATERIAL[name]) material.setName(ROLE_BY_MATERIAL[name]);
  }

  const wheels = {};
  for (const node of meshNodes) {
    const role = wheelRole(node.getName());
    if (!role) {
      node.setName('Body');
      continue;
    }
    const bounds = getBounds(node);
    const center = [0, 1, 2].map((k) => (bounds.min[k] + bounds.max[k]) / 2);
    // Задняя ось — одним мешем на оба колеса: центр по X ровно 0.
    if (role === 'Wheels_R') center[0] = 0;
    translateMesh(node.getMesh(), center);
    node.setTranslation(center).setName(role);
    wheels[role] = { center: center.map((v) => +v.toFixed(3)), radius: +((bounds.max[1] - bounds.min[1]) / 2).toFixed(3) };
  }

  await doc.transform(weld(), dedup(), prune());
  const out = path.join(outDir, `${vehicle.id}.glb`);
  await io.write(out, doc);
  const b = getBounds(root.listScenes()[0]);
  // Координаты для игры: Z перевёрнут относительно glTF.
  summary[vehicle.id] = {
    width: +(b.max[0] - b.min[0]).toFixed(3),
    height: +(b.max[1] - b.min[1]).toFixed(3),
    length: +(b.max[2] - b.min[2]).toFixed(3),
    wheelRadius: wheels.Wheel_FL.radius,
    frontAxleZ: +(-wheels.Wheel_FL.center[2]).toFixed(3),
    rearAxleZ: +(-wheels.Wheels_R.center[2]).toFixed(3),
  };
  console.log(`${out}: ${(fs.statSync(out).size / 1024).toFixed(0)} KB, flipped=${flip}`, JSON.stringify(summary[vehicle.id]));
}
