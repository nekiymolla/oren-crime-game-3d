import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shipping district contains no OSM calibration towers', () {
    for (final file in Directory(
      'assets/models/world/chunks',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.glb'))) {
      final data = file.readAsBytesSync();
      final header = ByteData.sublistView(data);
      final size = header.getUint32(12, Endian.little);
      final gltf = jsonDecode(utf8.decode(data.sublist(20, 20 + size)));
      for (final mesh in gltf['meshes'] as List? ?? []) {
        for (final primitive in mesh['primitives']) {
          final pos = gltf['accessors'][primitive['attributes']['POSITION']];
          expect(pos['max'][1] as num, lessThan(250), reason: file.path);
          expect(pos['min'][1] as num, greaterThan(-100), reason: file.path);
        }
      }
    }
  });

  test('every streamed chunk has bounded, indexed architecture details', () {
    final source = jsonDecode(
      File('assets/models/world/chunks/manifest.json').readAsStringSync(),
    );
    final summary =
        jsonDecode(
              File(
                'assets/models/world/details/manifest.json',
              ).readAsStringSync(),
            )
            as List;
    expect(summary.length, source['cells'].length);
    var triangles = 0, bytes = 0, roofs = 0;
    for (final cell in source['cells']) {
      final file = File('assets/models/world/details/${cell['file']}');
      final data = file.readAsBytesSync();
      bytes += data.length;
      final header = ByteData.sublistView(data);
      expect(header.getUint32(0, Endian.little), 0x46546c67);
      final length = header.getUint32(12, Endian.little);
      final gltf = jsonDecode(utf8.decode(data.sublist(20, 20 + length)));
      final accessors = gltf['accessors'] as List? ?? [];
      for (final accessor in accessors) {
        if (accessor['type'] == 'VEC3' && accessor['max'] != null) {
          expect(
            (accessor['max'][1] as num).abs(),
            lessThan(250),
            reason: cell['file'],
          );
        }
      }
      for (final mesh in gltf['meshes'] as List? ?? []) {
        for (final primitive in mesh['primitives']) {
          expect(primitive['indices'], isNotNull);
          final count = accessors[primitive['indices']]['count'] as int;
          expect(count % 3, 0);
          triangles += count ~/ 3;
        }
      }
      final stats = summary.singleWhere((s) => s['file'] == cell['file']);
      roofs += stats['pitched'] as int;
    }
    expect(triangles, inInclusiveRange(100000, 300000));
    expect(roofs, greaterThan(200));
    expect(bytes, lessThan(30 * 1024 * 1024));
  });
}
