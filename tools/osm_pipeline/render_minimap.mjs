// Рисует карту района для радара/компаса HUD (lib/ui/hud/radar.dart):
// вид сверху по той же 3D-геометрии чанков, что видит игра, — дома,
// асфальт, тротуары, земля. Пишет PNG и JSON с привязкой к мировым
// координатам игры (пиксель u -> +x, v -> +z; в игре север — +Z, см.
// calibration.json, так что на самой картинке север внизу — радар её
// поворачивает сам).
//
// Использование: node render_minimap.mjs <chunks_dir> <out.png> <out.json>
// (PNG кодирует ffmpeg из промежуточного PPM.)

import fs from 'fs';
import os from 'os';
import path from 'path';
import { execFileSync } from 'child_process';
import { loadChunkGeometry } from './chunk_geometry.mjs';

const [chunksDir, outPng, outJson] = process.argv.slice(2);
if (!outJson) {
  console.error('Использование: node render_minimap.mjs <chunks_dir> <out.png> <out.json>');
  process.exit(2);
}

const METERS_PER_PIXEL = 2;
const manifest = JSON.parse(fs.readFileSync(path.join(chunksDir, 'manifest.json'), 'utf8'));
const size = manifest.cellSizeMeters;
const minX = Math.min(...manifest.cells.map((c) => c.cellX)) * size;
const maxX = (Math.max(...manifest.cells.map((c) => c.cellX)) + 1) * size;
const minZ = Math.min(...manifest.cells.map((c) => c.cellZ)) * size;
const maxZ = (Math.max(...manifest.cells.map((c) => c.cellZ)) + 1) * size;
const width = Math.round((maxX - minX) / METERS_PER_PIXEL);
const height = Math.round((maxZ - minZ) / METERS_PER_PIXEL);

const geometry = await loadChunkGeometry(chunksDir);

// Не "хмурая" палитра: светлее и теплее, чем у GTA IV.
const GROUND = [92, 118, 84];
const ROAD = [176, 178, 176];
const WALK = [146, 148, 142];
const BUILDING = [222, 204, 172];
const BUILDING_EDGE = [150, 132, 104];

const kind = new Uint8Array(width * height); // 0 земля, 1 дорога, 2 тротуар, 3 дом
for (let py = 0; py < height; py++) {
  for (let px = 0; px < width; px++) {
    const x = minX + (px + 0.5) * METERS_PER_PIXEL;
    const z = minZ + (py + 0.5) * METERS_PER_PIXEL;
    const surface = geometry.topSurfaceAt(x, z);
    let k = 0;
    if (surface) {
      if (surface.y > 2.5) k = 3;
      else if (/ASPHALT|road_marking/.test(surface.material)) k = 1;
      else if (/EARTH/.test(surface.material)) k = 0;
      else k = 2;
    }
    kind[py * width + px] = k;
  }
}

const rgb = Buffer.alloc(width * height * 3);
for (let py = 0; py < height; py++) {
  for (let px = 0; px < width; px++) {
    const i = py * width + px;
    let color = [GROUND, ROAD, WALK, BUILDING][kind[i]];
    if (kind[i] === 3) {
      // Контур дома: край, где сосед — не дом.
      const edge = [[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => {
        const nx = px + dx;
        const ny = py + dy;
        return nx < 0 || ny < 0 || nx >= width || ny >= height || kind[ny * width + nx] !== 3;
      });
      if (edge) color = BUILDING_EDGE;
    }
    rgb.set(color, i * 3);
  }
}

const ppm = path.join(os.tmpdir(), `minimap_${process.pid}.ppm`);
fs.writeFileSync(ppm, Buffer.concat([Buffer.from(`P6\n${width} ${height}\n255\n`), rgb]));
execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-i', ppm, outPng]);
fs.unlinkSync(ppm);
fs.writeFileSync(
  outJson,
  JSON.stringify({ image: path.basename(outPng), minX, minZ, maxX, maxZ, metersPerPixel: METERS_PER_PIXEL, width, height }, null, 2) + '\n',
);
const counts = [0, 0, 0, 0];
for (const k of kind) counts[k]++;
console.log(`Карта ${width}x${height} пикс (${METERS_PER_PIXEL} м/пикс): земля ${counts[0]}, дороги ${counts[1]}, тротуары ${counts[2]}, дома ${counts[3]}`);
