// Находит маячок-якорь (см. add_anchor_node.py — искусственное "здание" с
// уникальной высотой ANCHOR_HEIGHT ровно в geoOrigin), вычисляет, куда
// osm2world поместил эту точку в своей локальной системе координат, и
// сдвигает ВСЮ геометрию так, чтобы geoOrigin оказался ровно в (0,0) —
// иначе спавн игрока не совпадает с домом, если узлы за пределами bbox
// (даже отфильтрованные filter_oversized_ways.py) сместили origin, который
// osm2world выбирает сам по общему разбросу узлов файла (см. PROGRESS.md).
//
// Вызывается из convert_to_glb.sh сразу после osm2world, до grid_split.mjs.
//
// Использование: node recenter.mjs <input.glb> <output.glb>
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { prune } from '@gltf-transform/functions';

const ANCHOR_HEIGHT_MIN = 10000; // см. ANCHOR_HEIGHT в add_anchor_node.py

const [, , srcPath, outPath] = process.argv;

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const doc = await io.read(srcPath);
const scene = doc.getRoot().listScenes()[0];

function collectMeshNodes(node, out) {
  if (node.getMesh()) out.push(node);
  for (const child of node.listChildren()) collectMeshNodes(child, out);
}
const meshNodes = [];
for (const child of scene.listChildren()) collectMeshNodes(child, meshNodes);

let anchorNode = null;
let anchorMinX = Infinity, anchorMaxX = -Infinity;
let anchorMinZ = Infinity, anchorMaxZ = -Infinity;

for (const node of meshNodes) {
  const mesh = node.getMesh();
  for (const prim of mesh.listPrimitives()) {
    const posAccessor = prim.getAttribute('POSITION');
    if (!posAccessor) continue;
    const arr = posAccessor.getArray();
    let hasAnchorHeight = false;
    for (let i = 1; i < arr.length; i += 3) {
      if (arr[i] >= ANCHOR_HEIGHT_MIN) {
        hasAnchorHeight = true;
        break;
      }
    }
    if (!hasAnchorHeight) continue;
    anchorNode = node;
    for (let i = 0; i < arr.length; i += 3) {
      anchorMinX = Math.min(anchorMinX, arr[i]);
      anchorMaxX = Math.max(anchorMaxX, arr[i]);
      anchorMinZ = Math.min(anchorMinZ, arr[i + 2]);
      anchorMaxZ = Math.max(anchorMaxZ, arr[i + 2]);
    }
  }
}

if (!anchorNode) {
  console.error(
    'Маячок-якорь не найден в сконвертированной геометрии (искали вершину ' +
      `с Y >= ${ANCHOR_HEIGHT_MIN}) — recenter пропущен, geoOrigin может не ` +
      'совпадать с (0,0). Проверь add_anchor_node.py и что osm2world не ' +
      'обрезал искусственное здание.',
  );
  await io.write(outPath, doc);
  process.exit(1);
}

const offsetX = (anchorMinX + anchorMaxX) / 2;
const offsetZ = (anchorMinZ + anchorMaxZ) / 2;
console.log(`Якорь найден на (${offsetX.toFixed(2)}, ${offsetZ.toFixed(2)}) — сдвигаю геометрию.`);

// Убираем сам маячок — он не часть реального мира.
anchorNode.getParentNode()?.removeChild(anchorNode);
anchorNode.dispose();

// Сдвигаем все оставшиеся позиции (X/Z; Y — высота — не трогаем).
const seen = new Set();
for (const node of meshNodes) {
  if (node === anchorNode) continue;
  const mesh = node.getMesh();
  if (!mesh) continue; // мог быть только что удалённый якорь
  for (const prim of mesh.listPrimitives()) {
    const posAccessor = prim.getAttribute('POSITION');
    if (!posAccessor || seen.has(posAccessor)) continue;
    seen.add(posAccessor);
    const arr = posAccessor.getArray();
    for (let i = 0; i < arr.length; i += 3) {
      arr[i] -= offsetX;
      arr[i + 2] -= offsetZ;
    }
    posAccessor.setArray(arr);
  }
}

await doc.transform(prune());
await io.write(outPath, doc);
console.log(`Готово: ${outPath}`);
