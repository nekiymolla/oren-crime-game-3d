// Проверяет, что пешеходные рёбра дорожного графа не проходят сквозь
// здания в РЕАЛЬНОЙ 3D-геометрии чанков (то, что видит игрок), а не в
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
// Использование: node check_pedestrian_graph.mjs <chunks_dir> <road_graph.json>

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
const SAMPLE_STEP = 0.5;
const GRID_CELL = 4;

const [chunksDir, graphPath] = process.argv.slice(2);
if (!chunksDir || !graphPath) {
  console.error('Использование: node check_pedestrian_graph.mjs <chunks_dir> <road_graph.json>');
  process.exit(2);
}

// Все треугольники чанков в мировых координатах + сетка для быстрого поиска.
const triangles = [];
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
    if (best === null || y > best) best = y;
  }
  return best;
}

const graph = JSON.parse(fs.readFileSync(graphPath, 'utf8'));
const nodes = Object.fromEntries(graph.nodes.map((n) => [n.id, n]));

let checked = 0;
const blocked = [];
for (const edge of graph.edges) {
  if (!PEDESTRIAN_HIGHWAYS.has(edge.highway)) continue;
  checked++;
  const a = nodes[edge.from];
  const b = nodes[edge.to];
  const length = Math.hypot(b.x - a.x, b.z - a.z);
  if (length < 1e-6) continue;
  const ux = (b.x - a.x) / length;
  const uz = (b.z - a.z) / length;

  search: for (let s = 0; s <= length; s += SAMPLE_STEP) {
    for (const side of [-BODY_RADIUS, 0, BODY_RADIUS]) {
      const x = a.x + ux * s - uz * side;
      const z = a.z + uz * s + ux * side;
      const h = topHeightAt(x, z);
      if (h !== null && h > ROOF_MIN_HEIGHT && h < ROOF_MAX_HEIGHT) {
        blocked.push({ highway: edge.highway, from: edge.from, to: edge.to, x: +x.toFixed(1), z: +z.toFixed(1), roof: +h.toFixed(1) });
        break search;
      }
    }
  }
}

console.log(`Пешеходный граф: проверено ${checked} рёбер по ${triangles.length} треугольникам, сквозь здания: ${blocked.length}`);
if (blocked.length > 0) {
  for (const b of blocked.slice(0, 20)) console.log('  ', JSON.stringify(b));
  process.exit(1);
}
