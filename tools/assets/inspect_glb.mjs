// Сводка по glb: треугольники, материалы, текстуры, скины, анимации.
// Использование: node tools/assets/inspect_glb.mjs <file.glb>...
import { NodeIO } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';

const io = new NodeIO().registerExtensions(ALL_EXTENSIONS);
for (const file of process.argv.slice(2)) {
  const doc = await io.read(file);
  const root = doc.getRoot();
  let tris = 0;
  for (const mesh of root.listMeshes()) {
    for (const p of mesh.listPrimitives()) {
      const idx = p.getIndices();
      tris += (idx ? idx.getCount() : p.getAttribute('POSITION').getCount()) / 3;
    }
  }
  const skins = root.listSkins().map((s) => s.listJoints().length);
  const anims = root.listAnimations().map((a) => a.getName());
  const mats = root.listMaterials().map((m) => m.getName());
  console.log(`${file.split('/').pop()}: tris=${tris} meshes=${root.listMeshes().length} mats=${mats.length}[${mats.join(',')}] tex=${root.listTextures().length} skins=${JSON.stringify(skins)}`);
  if (anims.length) console.log(`  anims(${anims.length}): ${anims.join(', ')}`);
}
