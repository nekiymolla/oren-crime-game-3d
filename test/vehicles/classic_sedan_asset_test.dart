import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crime_oren/vehicles/vehicle.dart';

void main() {
  test(
    'classic sedan asset matches the runtime wheel and collision contract',
    () {
      final bytes = File(
        'assets/models/vehicles/sedan_80.glb',
      ).readAsBytesSync();
      final data = ByteData.sublistView(bytes);
      expect(data.getUint32(0, Endian.little), 0x46546c67);
      final length = data.getUint32(12, Endian.little);
      final json =
          jsonDecode(utf8.decode(bytes.sublist(20, 20 + length)))
              as Map<String, dynamic>;
      final nodes = (json['nodes'] as List).cast<Map<String, dynamic>>();
      final byName = {for (final node in nodes) node['name']: node};
      expect(
        byName.keys,
        containsAll(['Body', 'Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR']),
      );
      for (final name in ['Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR']) {
        final p = (byName[name]!['translation'] as List).cast<num>();
        expect(p[1], closeTo(VehicleArchetype.classicSedan.wheelRadius, 1e-5));
        expect(p[2].isNegative, name.startsWith('Wheel_F'));
      }
      final summary =
          jsonDecode(
                File('assets/models/vehicles/sedan_80.json').readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(
        VehicleArchetype.classicSedan.bodyWidth,
        closeTo(summary['width'] as num, 0.001),
      );
      expect(
        VehicleArchetype.classicSedan.bodyLength,
        closeTo(summary['length'] as num, 0.001),
      );
      expect(
        VehicleArchetype.classicSedan.wheelbase,
        closeTo(summary['wheelbase'] as num, 0.001),
      );
      final materials = (json['materials'] as List)
          .map((m) => m['name'])
          .toSet();
      expect(
        materials,
        containsAll([
          'BodyTextured',
          'ClearGlass',
          'Headlights',
          'TailLights',
          'Tire',
        ]),
      );
      expect(summary['frontLampTriangles'], greaterThan(0));
      expect(summary['rearLampTriangles'], greaterThan(0));
      expect(bytes.length, lessThan(1500000));
    },
  );
}
