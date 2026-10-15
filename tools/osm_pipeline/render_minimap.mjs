// Рисует карту района для радара/компаса HUD (lib/ui/hud/radar.dart):
// вид сверху по той же 3D-геометрии чанков, что видит игра, — дома,
// асфальт, тротуары, земля. Пишет PNG и JSON с привязкой к мировым
// координатам игры (пиксель u -> +x, v -> +z; в игре север — +Z, см.
// calibration.json, так что на самой картинке север внизу — радар её
// поворачивает сам).
//
// Заодно пишет навигационную сетку nav_grid.bin (1 м на клетку, байт на
// клетку): 0 земля/газон, 1 крупная дорога (только машины), 2 мелкая
// дорога (машины, пешеходы могут переходить), 3 тротуар, 4 дом. По ней
// пешеходы бродят, не заходя в дома и на крупные дороги, а полосы трафика
// отбрасываются, если задевают не-асфальт (lib/world/nav_grid.dart).
// Тип дороги — по ближайшему ребру дорожного графа (road_graph.json рядом
// с out.json, в координатах игры).
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

// --- Навигационная сетка 1 м ---------------------------------------------
const NAV_CELL = 1;
const navWidth = Math.round((maxX - minX) / NAV_CELL);
const navHeight = Math.round((maxZ - minZ) / NAV_CELL);
const MAJOR = new Set(['tertiary', 'secondary', 'primary', 'trunk', 'motorway']);
const graph = JSON.parse(fs.readFileSync(path.join(path.dirname(outJson), 'road_graph.json'), 'utf8'));
const nodeById = new Map(graph.nodes.map((n) => [n.id, n]));
// Рёбра в корзинах по 16 м — ближайшее ребро ищется только рядом.
const BUCKET = 16;
const buckets = new Map();
for (const e of graph.edges) {
  const a = nodeById.get(e.from);
  const b = nodeById.get(e.to);
  if (!a || !b) continue;
  const seg = { ax: a.x, az: a.z, bx: b.x, bz: b.z, major: MAJOR.has(e.highway) };
  const x0 = Math.floor((Math.min(a.x, b.x) - 12) / BUCKET), x1 = Math.floor((Math.max(a.x, b.x) + 12) / BUCKET);
  const z0 = Math.floor((Math.min(a.z, b.z) - 12) / BUCKET), z1 = Math.floor((Math.max(a.z, b.z) + 12) / BUCKET);
  for (let i = x0; i <= x1; i++) for (let j = z0; j <= z1; j++) {
    const key = `${i},${j}`;
    if (!buckets.has(key)) buckets.set(key, []);
    buckets.get(key).push(seg);
  }
}
function nearestIsMajor(x, z) {
  let best = Infinity, major = false;
  for (const s of buckets.get(`${Math.floor(x / BUCKET)},${Math.floor(z / BUCKET)}`) ?? []) {
    const dx = s.bx - s.ax, dz = s.bz - s.az;
    const len2 = dx * dx + dz * dz || 1e-9;
    const t = Math.max(0, Math.min(1, ((x - s.ax) * dx + (z - s.az) * dz) / len2));
    const d = Math.hypot(s.ax + dx * t - x, s.az + dz * t - z);
    if (d < best) { best = d; major = s.major; }
  }
  // Асфальт далеко от любого ребра (площадки, парковки) — считаем мелким.
  return best <= 12 && major;
}
const nav = new Uint8Array(navWidth * navHeight);
const navCounts = [0, 0, 0, 0, 0];
for (let py = 0; py < navHeight; py++) {
  for (let px = 0; px < navWidth; px++) {
    const x = minX + (px + 0.5) * NAV_CELL;
    const z = minZ + (py + 0.5) * NAV_CELL;
    const surface = geometry.topSurfaceAt(x, z);
    let k = 0;
    if (surface) {
      if (surface.y > 2.5) k = 4;
      else if (/ASPHALT|road_marking/.test(surface.material)) k = nearestIsMajor(x, z) ? 1 : 2;
      else if (/EARTH/.test(surface.material)) k = 0;
      else k = 3;
    }
    nav[py * navWidth + px] = k;
    navCounts[k]++;
  }
}
const navFile = path.join(path.dirname(outJson), 'nav_grid.bin');
fs.writeFileSync(navFile, nav);
console.log(`Навсетка ${navWidth}x${navHeight} (${NAV_CELL} м): земля ${navCounts[0]}, крупные дороги ${navCounts[1]}, мелкие ${navCounts[2]}, тротуары ${navCounts[3]}, дома ${navCounts[4]}`);


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
  JSON.stringify(
    {
      image: path.basename(outPng),
      minX, minZ, maxX, maxZ,
      metersPerPixel: METERS_PER_PIXEL, width, height,
      nav: { file: 'nav_grid.bin', metersPerCell: NAV_CELL, width: navWidth, height: navHeight },
    },
    null,
    2,
  ) + '\n',
);
const counts = [0, 0, 0, 0];
for (const k of kind) counts[k]++;
console.log(`Карта ${width}x${height} пикс (${METERS_PER_PIXEL} м/пикс): земля ${counts[0]}, дороги ${counts[1]}, тротуары ${counts[2]}, дома ${counts[3]}`);
