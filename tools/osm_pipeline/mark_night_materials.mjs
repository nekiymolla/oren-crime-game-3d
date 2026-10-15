// Помечает в чанках района материалы, которые игра меняет в рантайме.
// Движок не хранит имена материалов glTF, поэтому найти "Windows" или
// "ASPHALT" по имени игра не может — нужны метки, которых не видно глазом:
//
// - окна домов светятся ночью. Метка — emissive-текстура (та же, что
//   базовая: рисунок окон) при НУЛЕВОМ emissiveFactor: днём окна выглядят
//   как раньше, а игра ночью поднимает им яркость
//   (lib/time/day_night_view.dart);
// - дороги и тротуары мокнут в дождь. Метка — roughnessFactor 0.987
//   вместо 1 (на глаз неотличимо), игра сравнивает с допуском и в дождь
//   делает их гладкими, чтобы в них отражался неон
//   (lib/weather/wet_roads_view.dart, значение там же — WetRoadsView.marker).
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
// Имена материалов osm2world, которые мокнут в дождь.
const WET_MATERIALS = new Set(['ASPHALT', 'PAVING_STONE', 'road_marking_dash']);
const WET_MARKER_ROUGHNESS = 0.987;

const [chunksDir] = process.argv.slice(2);
if (!chunksDir) {
  console.error('Использование: node mark_night_materials.mjs <chunks_dir>');
  process.exit(2);
}

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
let marked = 0;
let markedWet = 0;
let files = 0;
for (const file of fs.readdirSync(chunksDir).filter((f) => f.endsWith('.glb'))) {
  const filePath = path.join(chunksDir, file);
  const doc = await io.read(filePath);
  let changed = false;
  for (const material of doc.getRoot().listMaterials()) {
    if (WET_MATERIALS.has(material.getName()) && material.getRoughnessFactor() !== WET_MARKER_ROUGHNESS) {
      material.setRoughnessFactor(WET_MARKER_ROUGHNESS);
      markedWet++;
      changed = true;
    }
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
console.log(`Помечено: ночных ${marked}, мокнущих ${markedWet}; изменено чанков: ${files}`);
