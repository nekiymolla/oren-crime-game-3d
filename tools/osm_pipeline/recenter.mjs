// Находит три маячка-якоря (см. add_anchor_node.py — искусственные "здания"
// с уникальными высотами ровно в geoOrigin/+200м на север/+200м на восток),
// вычисляет полную афинную калибровку lat/lon -> локальные координаты игры
// (не только сдвиг, но и фактическое направление/масштаб осей X/Z, как их
// выбрал osm2world) и:
//   1) сдвигает ВСЮ геометрию так, чтобы geoOrigin оказался ровно в (0,0);
//   2) пишет calibration.json — по нему build_road_graph.mjs проецирует
//      узлы дорожного графа в ТУ ЖЕ систему координат, не прогоняя их
//      заново через osm2world.
// Без калибровки узлы за пределами bbox (даже отфильтрованные
// filter_oversized_ways.py) незаметно смещают origin, который osm2world
// выбирает сам по общему разбросу узлов файла (см. PROGRESS.md).
//
// Вызывается из convert_to_glb.sh сразу после osm2world, до grid_split.mjs.
//
// Использование: node recenter.mjs <input.glb> <output.glb> <calibration.json> <originLat> <originLon>
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { prune } from '@gltf-transform/functions';
import fs from 'fs';

// См. ANCHORS в add_anchor_node.py.
const ANCHOR_HEIGHTS = { origin: 12345, north: 23456, east: 34567 };
const ANCHOR_OFFSET_METERS = 200.0; // см. ANCHOR_OFFSET_METERS в add_anchor_node.py

const [, , srcPath, outPath, calibrationPath, originLatArg, originLonArg] = process.argv;
const originLat = Number(originLatArg);
const originLon = Number(originLonArg);

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(srcPath);
const scene = doc.getRoot().listScenes()[0];

function collectMeshNodes(node, out) {
  if (node.getMesh()) out.push(node);
  for (const child of node.listChildren()) collectMeshNodes(child, out);
}
const meshNodes = [];
for (const child of scene.listChildren()) collectMeshNodes(child, meshNodes);

// Находим для каждой высоты-маркера её узел и центроид XZ.
const found = {}; // name -> { node, x, z }
for (const node of meshNodes) {
  const mesh = node.getMesh();
  for (const prim of mesh.listPrimitives()) {
    const posAccessor = prim.getAttribute('POSITION');
    if (!posAccessor) continue;
    const arr = posAccessor.getArray();
    let maxY = -Infinity;
    for (let i = 1; i < arr.length; i += 3) maxY = Math.max(maxY, arr[i]);

    for (const [name, height] of Object.entries(ANCHOR_HEIGHTS)) {
      if (Math.abs(maxY - height) > 1) continue;
      let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
      for (let i = 0; i < arr.length; i += 3) {
        minX = Math.min(minX, arr[i]);
        maxX = Math.max(maxX, arr[i]);
        minZ = Math.min(minZ, arr[i + 2]);
        maxZ = Math.max(maxZ, arr[i + 2]);
      }
      found[name] = { node, x: (minX + maxX) / 2, z: (minZ + maxZ) / 2 };
    }
  }
}

const missing = Object.keys(ANCHOR_HEIGHTS).filter((name) => !found[name]);
if (missing.length > 0) {
  console.error(
    `Маячки не найдены: ${missing.join(', ')} — recenter пропущен, geoOrigin ` +
      'может не совпадать с (0,0), калибровка дорожного графа недоступна. ' +
      'Проверь add_anchor_node.py и что osm2world не обрезал искусственные здания.',
  );
  await io.write(outPath, doc);
  process.exit(1);
}

const origin = found.origin;
console.log(`Якорь найден на (${origin.x.toFixed(2)}, ${origin.z.toFixed(2)}) — сдвигаю геометрию.`);

// Единичные векторы "метр на север" / "метр на восток" в локальных
// координатах — эмпирически, без предположений о формуле проекции внутри
// osm2world (см. заголовок файла).
const eastUnit = {
  x: (found.east.x - origin.x) / ANCHOR_OFFSET_METERS,
  z: (found.east.z - origin.z) / ANCHOR_OFFSET_METERS,
};
const northUnit = {
  x: (found.north.x - origin.x) / ANCHOR_OFFSET_METERS,
  z: (found.north.z - origin.z) / ANCHOR_OFFSET_METERS,
};

fs.writeFileSync(
  calibrationPath,
  JSON.stringify(
    {
      originLat,
      originLon,
      metersPerDegreeLat: 111320.0,
      metersPerDegreeLon: 111320.0 * Math.cos((originLat * Math.PI) / 180),
      eastUnit,
      northUnit,
    },
    null,
    2,
  ),
);
console.log(`Калибровка записана: ${calibrationPath}`);

// Убираем сами маячки — они не часть реального мира.
for (const { node } of Object.values(found)) {
  node.getParentNode()?.removeChild(node);
  node.dispose();
}

// Сдвигаем все оставшиеся позиции (X/Z; Y — высота — не трогаем).
const anchorNodes = new Set(Object.values(found).map((a) => a.node));
const seen = new Set();
for (const node of meshNodes) {
  if (anchorNodes.has(node)) continue;
  const mesh = node.getMesh();
  if (!mesh) continue; // мог быть только что удалённый якорь
  for (const prim of mesh.listPrimitives()) {
    const posAccessor = prim.getAttribute('POSITION');
    if (!posAccessor || seen.has(posAccessor)) continue;
    seen.add(posAccessor);
    const arr = posAccessor.getArray();
    for (let i = 0; i < arr.length; i += 3) {
      arr[i] -= origin.x;
      arr[i + 2] -= origin.z;
    }
    posAccessor.setArray(arr);
  }
}

await doc.transform(prune());
await io.write(outPath, doc);
console.log(`Готово: ${outPath}`);
