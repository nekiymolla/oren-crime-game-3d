import 'dart:io';

import 'package:flutter_scene/build_hooks.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    // flutter_scene currently watches only the discovery root's direct
    // children. Also watch nested directories so adding a new vehicle or
    // character really imports it on the next build.
    final assets = Directory.fromUri(input.packageRoot.resolve('assets/'));
    if (assets.existsSync()) {
      output.dependencies.addAll(
        assets
            .listSync(recursive: true, followLinks: false)
            .whereType<Directory>()
            .map((directory) => directory.uri),
      );
    }
    // flutter_scene:init:start
    // Import .glb and .fscene sources under assets/, loadable by source path
    // with loadScene (and hot-reloadable). A no-op when there are no scenes.
    buildScenes(buildInput: input, buildOutput: output);
    // Compile .fmat materials under assets/, loadable by source path with
    // loadFmatMaterial (and hot-reloadable). A no-op when there are none.
    await buildMaterials(buildInput: input, buildOutput: output);
    // flutter_scene:init:end
  });
}
