// Проверяет, что ни пешеходы, ни фоновый трафик, двигаясь по дорожному
// графу, не проходят сквозь здания в РЕАЛЬНОЙ 3D-геометрии чанков (то, что видит игрок), а не в
// контурах OSM: здания рисует osm2world, и сравнивать надо с ним.
//
// Пешеход ходит строго по прямой между узлами графа (lib/pedestrians/
// pedestrian.dart), так что если ни одно ребро не проходит под крышей —
// пройти сквозь дом он не может в принципе. Баг "пешеходы сквозь стены"
// (BUGS.md) три раза пытались чинить рейкастами в рантайме; эта проверка
// 14.10.2026 показала, что на текущих данных таких рёбер ноль.
//
// Вызывается из convert_to_glb.sh после сборки чанков и графа — чтобы
// пересборка карты не вернула баг молча. Код выхода 1, если нашлись рёбра.
//
// Трафик (lib/traffic/traffic_car.dart) ездит по правой полосе — со
// сдвигом laneOffsetFor(highway) от оси, поэтому для него проверяется
// полоса целиком (оба борта кузова) в каждом разрешённом направлении ребра:
// и что не сквозь дома, и что кузов на асфальте, а не на тротуаре/газоне
// (14.10.2026 на узких дворовых дорогах машины свешивались на тротуар).
//
// Использование: node check_road_graph.mjs <chunks_dir> <road_graph.json>

import fs from 'fs';
import { NodeIO } from '@gltf-transform/core';

// Те же типы, что pedestrianHighwayTypes в lib/pedestrians/pedestrian.dart —
// при изменении менять в обоих местах.
const PEDESTRIAN_HIGHWAYS = new Set([
  'footway', 'path', 'pedestrian', 'living_street',
  'residential', 'unclassified', 'service', 'steps',
]);

// Выше этого над точкой — крыша/стена дома, а не дорога или газон.
const ROOF_MIN_HEIGHT = 1.5;
// Служебный якорный узел пайплайна висит на ~23 км (add_anchor_node.py) —
// он не геометрия мира.
const ROOF_MAX_HEIGHT = 100;
// Полуширина капсулы пешехода (PedestrianSystem._radius) — проверяем не
// только ось ребра, но и по бокам, иначе капсула торчала бы из стены.
const BODY_RADIUS = 0.3;
// Те же, что trafficHighwayTypes / trafficLaneOffset в
// lib/traffic/traffic_car.dart — при изменении менять в обоих местах.
const TRAFFIC_HIGHWAYS = new Set([
  'residential', 'unclassified', 'tertiary', 'secondary', 'primary', 'living_street',
]);
const laneOffsetFor = (highway) => (highway === 'residential' || highway === 'living_street' ? 1.2 : 1.75);
const CAR_HALF_WIDTH = 0.9;
// Сколько борта может быть на бордюре (дворовая полоса 1.2 + 0.9 = 2.1 при
// асфальте до ~2.0 м).
const CURB_TOLERANCE = 0.15;
// Доля точек под кузовом, которые обязаны быть асфальтом. Не 100%: на
// перекрёстках и съездах osm2world кладёт другие поверхности.
const MIN_ASPHALT_SHARE = 0.97;
// EARTH — грунтовки (surface=unpaved, например Смоленская улица): дорога,
// просто без асфальта. Плитка (PAVING_STONE) — пешеходные площади, по ним
// машинам нельзя.
const isRoadSurface = (material) => /ASPHALT|road_marking|EARTH/.test(material);
const SAMPLE_STEP = 0.5;
const GRID_CELL = 4;

const [chunksDir, graphPath] = process.argv.slice(2);
if (!chunksDir || !graphPath) {
  console.error('Использование: node check_road_graph.mjs <chunks_dir> <road_graph.json>');
  process.exit(2);
}

// Все треугольники чанков в мировых координатах + сетка для быстрого поиска.
const triangles = [];
const triangleMaterials = [];
const grid = new Map();
const cellKey = (i, j) => `${i},${j}`;

const transform = (m, x, y, z) => [
  m[0] * x + m[4] * y + m[8] * z + m[12],
  m[1] * x + m[5] * y + m[9] * z + m[13],
  m[2] * x + m[6] * y + m[10] * z + m[14],
];

const io = new NodeIO();
for (const file of fs.readdirSync(chunksDir).filter((f) => f.endsWith('.glb'))) {
  const doc = await io.read(`${chunksDir}/${file}`);
  for (const node of doc.getRoot().listNodes()) {
    const mesh = node.getMesh();
    if (!mesh) continue;
    const matrix = node.getWorldMatrix();
    for (const primitive of mesh.listPrimitives()) {
      const material = primitive.getMaterial()?.getName() ?? '';
      const positions = primitive.getAttribute('POSITION');
      const indices = primitive.getIndices();
      const count = indices ? indices.getCount() : positions.getCount();
      const v = [0, 0, 0];
      for (let t = 0; t + 2 < count; t += 3) {
        const tri = [];
        for (let k = 0; k < 3; k++) {
          positions.getElement(indices ? indices.getScalar(t + k) : t + k, v);
          tri.push(transform(matrix, v[0], v[1], v[2]));
        }
        const id = triangles.length;
        triangles.push(tri);
        triangleMaterials.push(material);
        const xs = tri.map((p) => p[0]);
        const zs = tri.map((p) => p[2]);
        for (let i = Math.floor(Math.min(...xs) / GRID_CELL); i <= Math.floor(Math.max(...xs) / GRID_CELL); i++) {
          for (let j = Math.floor(Math.min(...zs) / GRID_CELL); j <= Math.floor(Math.max(...zs) / GRID_CELL); j++) {
            const key = cellKey(i, j);
            if (!grid.has(key)) grid.set(key, []);
            grid.get(key).push(id);
          }
        }
      }
    }
  }
}

// Высота самой верхней геометрии над точкой (x, z) — как вертикальный луч
// сверху вниз; null, если там ничего нет (плейсхолдер-земля).
function topHeightAt(x, z) {
  return topSurfaceAt(x, z)?.y ?? null;
}

// То же, но с материалом поверхности. Выше ROOF_MAX_HEIGHT — служебный
// якорный узел, не мир.
function topSurfaceAt(x, z) {
  let best = null;
  for (const id of grid.get(cellKey(Math.floor(x / GRID_CELL), Math.floor(z / GRID_CELL))) ?? []) {
    const [a, b, c] = triangles[id];
    const det = (b[2] - c[2]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[2] - c[2]);
    if (Math.abs(det) < 1e-9) continue;
    const l1 = ((b[2] - c[2]) * (x - c[0]) + (c[0] - b[0]) * (z - c[2])) / det;
    const l2 = ((c[2] - a[2]) * (x - c[0]) + (a[0] - c[0]) * (z - c[2])) / det;
    const l3 = 1 - l1 - l2;
    if (l1 < 0 || l2 < 0 || l3 < 0) continue;
    const y = l1 * a[1] + l2 * b[1] + l3 * c[1];
    if (y < ROOF_MAX_HEIGHT && (best === null || y > best.y)) best = { y, material: triangleMaterials[id] };
  }
  return best;
}

const graph = JSON.parse(fs.readFileSync(graphPath, 'utf8'));
const nodes = Object.fromEntries(graph.nodes.map((n) => [n.id, n]));

// Первое место на прямой a -> b (со смещениями [offsets] вправо от
// направления), где над дорогой оказывается дом; null — чисто.
function findRoofAlong(a, b, offsets) {
  const length = Math.hypot(b.x - a.x, b.z - a.z);
  if (length < 1e-6) return null;
  const ux = (b.x - a.x) / length;
  const uz = (b.z - a.z) / length;
  for (let s = 0; s <= length; s += SAMPLE_STEP) {
    for (const offset of offsets) {
      // Вправо от направления (ux, uz) в координатах игры — (-uz, ux).
      const x = a.x + ux * s - uz * offset;
      const z = a.z + uz * s + ux * offset;
      const h = topHeightAt(x, z);
      if (h !== null && h > ROOF_MIN_HEIGHT && h < ROOF_MAX_HEIGHT) {
        return { x: +x.toFixed(1), z: +z.toFixed(1), roof: +h.toFixed(1) };
      }
    }
  }
  return null;
}

let failed = false;

// Пешеходы: ось ребра плюс ширина капсулы в обе стороны.
{
  let checked = 0;
  const blocked = [];
  for (const edge of graph.edges) {
    if (!PEDESTRIAN_HIGHWAYS.has(edge.highway)) continue;
    checked++;
    const hit = findRoofAlong(nodes[edge.from], nodes[edge.to], [-BODY_RADIUS, 0, BODY_RADIUS]);
    if (hit) blocked.push({ highway: edge.highway, from: edge.from, to: edge.to, ...hit });
  }
  report(`Пешеходы: проверено ${checked} рёбер`, blocked);
}

// Трафик: правая полоса в каждом разрешённом направлении (на oneway — по
// оси, как и в игре), оба борта кузова.
{
  let checked = 0;
  const blocked = [];
  for (const edge of graph.edges) {
    if (!TRAFFIC_HIGHWAYS.has(edge.highway)) continue;
    const center = edge.oneway ? 0 : laneOffsetFor(edge.highway);
    const offsets = [center - CAR_HALF_WIDTH, center, center + CAR_HALF_WIDTH];
    const directions = edge.oneway ? [[edge.from, edge.to]] : [[edge.from, edge.to], [edge.to, edge.from]];
    for (const [from, to] of directions) {
      checked++;
      const hit = findRoofAlong(nodes[from], nodes[to], offsets);
      if (hit) blocked.push({ highway: edge.highway, from, to, ...hit });
    }
  }
  report(`Трафик: проверено ${checked} полос`, blocked);
}

// Трафик: кузов на асфальте — центр полосы и оба борта (минус допуск на
// бордюр), каждые SAMPLE_STEP метров, без 3 м у узлов (там перекрёсток).
{
  let samples = 0;
  let onRoad = 0;
  const worst = [];
  for (const edge of graph.edges) {
    if (!TRAFFIC_HIGHWAYS.has(edge.highway)) continue;
    const center = edge.oneway ? 0 : laneOffsetFor(edge.highway);
    const side = CAR_HALF_WIDTH - CURB_TOLERANCE;
    const directions = edge.oneway ? [[edge.from, edge.to]] : [[edge.from, edge.to], [edge.to, edge.from]];
    for (const [from, to] of directions) {
      const a = nodes[from];
      const b = nodes[to];
      const length = Math.hypot(b.x - a.x, b.z - a.z);
      if (length < 7) continue;
      const ux = (b.x - a.x) / length;
      const uz = (b.z - a.z) / length;
      let edgeSamples = 0;
      let edgeOnRoad = 0;
      for (let s = 3; s <= length - 3; s += SAMPLE_STEP) {
        for (const offset of [center - side, center, center + side]) {
          const surface = topSurfaceAt(a.x + ux * s - uz * offset, a.z + uz * s + ux * offset);
          edgeSamples++;
          if (surface && isRoadSurface(surface.material)) edgeOnRoad++;
        }
      }
      samples += edgeSamples;
      onRoad += edgeOnRoad;
      if (edgeSamples > 0 && edgeOnRoad / edgeSamples < 0.9) {
        worst.push({ highway: edge.highway, from, to, onRoad: +(edgeOnRoad / edgeSamples).toFixed(2) });
      }
    }
  }
  const share = samples ? onRoad / samples : 1;
  console.log(`Трафик: под кузовом проезжая часть в ${(share * 100).toFixed(1)}% точек (нужно ${MIN_ASPHALT_SHARE * 100}%), полос хуже 90%: ${worst.length}`);
  for (const w of worst.slice(0, 10)) console.log('  ', JSON.stringify(w));
  if (share < MIN_ASPHALT_SHARE) failed = true;
}

function report(title, blocked) {
  console.log(`${title} по ${triangles.length} треугольникам, сквозь здания: ${blocked.length}`);
  for (const b of blocked.slice(0, 20)) console.log('  ', JSON.stringify(b));
  if (blocked.length > 0) failed = true;
}

if (failed) process.exit(1);
