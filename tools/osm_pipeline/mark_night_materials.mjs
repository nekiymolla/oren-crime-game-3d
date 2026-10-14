// Помечает в чанках района материалы, которые ночью светятся, — окна
// домов. Движок не хранит имена материалов glTF в рантайме, поэтому игра
// не может найти "Windows" по имени. Метка — emissive-текстура (та же, что
// базовая: рисунок окон) при НУЛЕВОМ emissiveFactor: днём окна выглядят как
// раньше, а игра находит материалы с emissive-текстурой и ночью поднимает
// им яркость (lib/time/day_night_view.dart).
//
// Идемпотентен: повторный прогон по уже помеченным чанкам ничего не
// меняет. Вызывается из convert_to_glb.sh после grid_split.mjs.
//
// Использование: node mark_night_materials.mjs <chunks_dir>

import fs from 'fs';
import path from 'path';
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';

// Имена материалов osm2world, которые светятся ночью.
const NIGHT_GLOW_MATERIALS = new Set(['Windows']);

const [chunksDir] = process.argv.slice(2);
if (!chunksDir) {
  console.error('Использование: node mark_night_materials.mjs <chunks_dir>');
  process.exit(2);
}

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
let marked = 0;
let files = 0;
for (const file of fs.readdirSync(chunksDir).filter((f) => f.endsWith('.glb'))) {
  const filePath = path.join(chunksDir, file);
  const doc = await io.read(filePath);
  let changed = false;
  for (const material of doc.getRoot().listMaterials()) {
    if (!NIGHT_GLOW_MATERIALS.has(material.getName())) continue;
    const texture = material.getBaseColorTexture();
    if (!texture || material.getEmissiveTexture() === texture) continue;
    material.setEmissiveTexture(texture);
    material.setEmissiveFactor([0, 0, 0]);
    marked++;
    changed = true;
  }
  if (changed) {
    await io.write(filePath, doc);
    files++;
  }
}
console.log(`Ночные материалы: помечено ${marked} в ${files} чанках`);
