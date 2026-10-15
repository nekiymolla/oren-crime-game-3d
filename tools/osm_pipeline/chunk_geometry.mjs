// Геометрия чанков района для офлайн-проверок пайплайна: все треугольники в
// мировых координатах и "вертикальный луч сверху" — что лежит над точкой
// (x, z) и из какого материала. Общий модуль для check_road_graph.mjs и
// filter_neon_signs.mjs.

import fs from 'fs';
import { NodeIO } from '@gltf-transform/core';

const GRID_CELL = 4;
// Служебный якорный узел пайплайна висит на ~23 км (add_anchor_node.py) —
// он не геометрия мира.
const ROOF_MAX_HEIGHT = 100;

export async function loadChunkGeometry(chunksDir) {
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

  // Самая верхняя поверхность над точкой (x, z) с материалом; null — там
  // ничего нет (плейсхолдер-земля).
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

  return {
    triangleCount: triangles.length,
    topSurfaceAt,
    topHeightAt: (x, z) => topSurfaceAt(x, z)?.y ?? null,
  };
}
