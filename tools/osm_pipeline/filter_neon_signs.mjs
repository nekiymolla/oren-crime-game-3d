// Отбирает неоновые вывески из кандидатов place_neon_signs.py по настоящей
// 3D-геометрии чанков: стена из OSM должна совпадать со стеной, которую
// нарисовал osm2world. За вывеской — дом не ниже [MIN_WALL_HEIGHT], перед
// ней — свободно (не повиснет внутри соседнего здания или над крышей
// пристройки). Потом прореживает: не ближе [SPACING] м друг к другу —
// неон акцент, а не гирлянда.
//
// Использование: node filter_neon_signs.mjs <chunks_dir> <candidates.json> <out neon_signs.json>

import fs from 'fs';
import { loadChunkGeometry } from './chunk_geometry.mjs';

const MIN_WALL_HEIGHT = 4.5; // вывеска на ~3.3 м — над ней должна быть стена
const ROOF_MIN = 1.5;
const SPACING = 35;
const MAX_SIGNS = 45;
// Сколько цветов в палитре игры (lib/world/neon_signs.dart).
const PALETTE_SIZE = 5;
const VARIANTS = 3;

const [chunksDir, candidatesPath, outPath] = process.argv.slice(2);
if (!chunksDir || !candidatesPath || !outPath) {
  console.error('Использование: node filter_neon_signs.mjs <chunks_dir> <candidates.json> <out.json>');
  process.exit(2);
}

const geometry = await loadChunkGeometry(chunksDir);
const candidates = JSON.parse(fs.readFileSync(candidatesPath, 'utf8'));

// Детерминированный "случайный" порядок и выбор цвета — от координат.
const hash = (x, z) => {
  let h = Math.imul(Math.round(x * 10) | 0, 73856093) ^ Math.imul(Math.round(z * 10) | 0, 19349663);
  h = Math.imul(h ^ (h >>> 13), 0x5bd1e995);
  return (h ^ (h >>> 15)) >>> 0;
};

const fits = (c) => {
  // Немного внутрь — стена дома нужной высоты; по всей ширине вывески.
  const tx = -c.nz;
  const tz = c.nx;
  for (const side of [-1, 0, 1]) {
    const ox = tx * side * 1.2;
    const oz = tz * side * 1.2;
    const behind = geometry.topHeightAt(c.x + ox - c.nx * 0.8, c.z + oz - c.nz * 0.8);
    if (behind === null || behind < MIN_WALL_HEIGHT) return false;
    for (const ahead of [0.6, 1.5, 3.0]) {
      const h = geometry.topHeightAt(c.x + ox + c.nx * ahead, c.z + oz + c.nz * ahead);
      if (h !== null && h > ROOF_MIN) return false;
    }
  }
  return true;
};

const valid = candidates.filter(fits).sort((a, b) => hash(a.x, a.z) - hash(b.x, b.z));
const chosen = [];
for (const c of valid) {
  if (chosen.length >= MAX_SIGNS) break;
  if (chosen.some((s) => Math.hypot(s.x - c.x, s.z - c.z) < SPACING)) continue;
  const h = hash(c.x, c.z);
  chosen.push({
    x: c.x,
    z: c.z,
    nx: c.nx,
    nz: c.nz,
    width: Math.round(Math.min(Math.max(c.wall * 0.45, 2.2), 4.5) * 10) / 10,
    color: h % PALETTE_SIZE,
    variant: (h >>> 8) % VARIANTS,
  });
}

fs.writeFileSync(outPath, JSON.stringify({ signs: chosen }, null, 1));
console.log(`Неон: из ${candidates.length} кандидатов на стенах ${valid.length} совпали с геометрией, выбрано ${chosen.length} -> ${outPath}`);
