// Разбивает сырой .glb квартала (выход osm2world) на пространственные
// ячейки (грид по X/Z), чтобы игра могла держать в сцене и в raycast-
// коллизиях только ближние к игроку чанки (см. lib/world/district_streamer.dart).
// Без этого весь квартал (~1900x1600 м реальной геометрии) рендерился и
// проверялся на коллизии целиком каждый кадр, независимо от позиции
// игрока — см. PROGRESS.md, диагностика лагов на слабом Android-устройстве.
//
// cellSizeMeters должен совпадать по смыслу с chunkSizeMeters в
// assets/data/world.json. Вызывается из convert_to_glb.sh, руками обычно
// не нужен.
//
// Использование: node grid_split.mjs <input.glb> <outDir> <cellSizeMeters>
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { prune, cloneDocument, getBounds } from '@gltf-transform/functions';
import fs from 'fs';
import path from 'path';

const [, , srcPath, outDir, cellSizeArg] = process.argv;
const CELL_SIZE = Number(cellSizeArg || 40);

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
const srcDoc = await io.read(srcPath);
const srcScene = srcDoc.getRoot().listScenes()[0];

function collectMeshNodes(node, out) {
  if (node.getMesh()) out.push(node);
  for (const child of node.listChildren()) collectMeshNodes(child, out);
}
const meshNodes = [];
for (const child of srcScene.listChildren()) collectMeshNodes(child, meshNodes);

// Тегируем каждый меш-узел уникальным индексом в extras — так найдём
// "того же" узла после clone() (ссылки на объекты меняются между
// документами, а extras копируются вместе с узлом).
meshNodes.forEach((node, i) => {
  node.setExtras({ ...node.getExtras(), cellSplitIndex: i });
});

const cellOf = (node) => {
  // osm2world печёт мировые координаты прямо в вершины, а не в transform
  // узла (transform у большинства узлов ~identity) — поэтому берём
  // реальный bounding box геометрии, а не getWorldTranslation().
  const { min, max } = getBounds(node);
  const x = (min[0] + max[0]) / 2;
  const z = (min[2] + max[2]) / 2;
  return { cx: Math.floor(x / CELL_SIZE), cz: Math.floor(z / CELL_SIZE), x, z };
};

const cellMap = new Map(); // "cx_cz" -> [{index, x, z}]
meshNodes.forEach((node, i) => {
  const { cx, cz, x, z } = cellOf(node);
  const key = `${cx}_${cz}`;
  if (!cellMap.has(key)) cellMap.set(key, []);
  cellMap.get(key).push({ index: i, x, z });
});

console.log(`Всего меш-узлов: ${meshNodes.length}, ячеек: ${cellMap.size} (размер ячейки ${CELL_SIZE} м)`);

fs.mkdirSync(outDir, { recursive: true });
const manifestCells = [];

for (const [key, entries] of cellMap.entries()) {
  const wanted = new Set(entries.map((e) => e.index));
  const cellDoc = cloneDocument(srcDoc);
  const cellScene = cellDoc.getRoot().listScenes()[0];

  const inClone = [];
  function collect(node) {
    if (node.getMesh()) inClone.push(node);
    for (const c of node.listChildren()) collect(c);
  }
  for (const child of cellScene.listChildren()) collect(child);

  for (const node of inClone) {
    const idx = node.getExtras().cellSplitIndex;
    if (!wanted.has(idx)) {
      node.getParentNode()?.removeChild(node);
      node.dispose();
    } else {
      // Извлекли ячейку — тег больше не нужен в готовом ассете.
      const extras = { ...node.getExtras() };
      delete extras.cellSplitIndex;
      node.setExtras(extras);
    }
  }

  await cellDoc.transform(prune());

  const [cx, cz] = key.split('_').map(Number);
  const xs = entries.map((e) => e.x);
  const zs = entries.map((e) => e.z);
  const fileName = `district_${key}.glb`;
  await io.write(path.join(outDir, fileName), cellDoc);

  // Манифест — в координатах игры: движок при загрузке .glb переворачивает
  // Z (z_игры = −z_glTF), а стример чанков сравнивает ячейки с позицией
  // игрока в игре. Ячейка glTF [cz*S, (cz+1)*S) в игре — [−(cz+1)*S, −cz*S),
  // т.е. номер −cz−1. Имена файлов остаются по glTF-ячейке.
  manifestCells.push({
    id: key,
    file: fileName,
    cellX: cx,
    cellZ: -cz - 1,
    centerX: (Math.min(...xs) + Math.max(...xs)) / 2,
    centerZ: -(Math.min(...zs) + Math.max(...zs)) / 2,
    nodeCount: entries.length,
  });

  console.log(`  ${fileName}: ${entries.length} узлов`);
}

fs.writeFileSync(
  path.join(outDir, 'manifest.json'),
  JSON.stringify({ cellSizeMeters: CELL_SIZE, cells: manifestCells }, null, 2),
);
console.log('Готово, manifest.json записан.');
