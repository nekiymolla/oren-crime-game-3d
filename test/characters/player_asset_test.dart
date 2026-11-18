import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crime_oren/characters/character_library.dart';
import 'package:crime_oren/characters/character_animation.dart';

void main() {
  test('new hero uses his own skeleton; existing NPCs keep their carriers', () {
    final roster = CharacterRoster.fromJson(
      jsonDecode(File('assets/data/characters.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    expect(roster.player, 'male_camper');
    expect(roster.animationCarrierFor(roster.player), 'male_camper');
    expect(roster.animationCarrierFor('male_casual'), 'male_casual');
    expect(roster.animationCarrierFor('female_punk'), 'female_casual');
    for (final id in roster.allIds) {
      expect(
        File('assets/models/characters/$id.glb').existsSync(),
        isTrue,
        reason: id,
      );
    }
  });

  test('hero contains all gameplay clips bound to his own 24-joint rig', () {
    final bytes = File(
      'assets/models/characters/male_camper.glb',
    ).readAsBytesSync();
    final data = ByteData.sublistView(bytes);
    final length = data.getUint32(12, Endian.little);
    final json =
        jsonDecode(utf8.decode(bytes.sublist(20, 20 + length)))
            as Map<String, dynamic>;
    expect((json['skins'] as List).single['joints'].length, 24);
    final animations = (json['animations'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      animations.map((a) => a['name']),
      containsAll(CharacterAnim.values.map((a) => a.clipName)),
    );
    final nodes = json['nodes'] as List;
    final armature = nodes.firstWhere((n) => n['name'] == 'Armature');
    expect(armature['scale'] ?? [1, 1, 1], [1, 1, 1]);
    final hips = nodes.firstWhere((n) => n['name'] == 'Hips');
    expect((hips['translation'][1] as num).abs(), lessThan(2));
    for (final animation in animations) {
      for (final channel in animation['channels'] as List) {
        final node = channel['target']['node'] as int;
        expect(node, inInclusiveRange(0, nodes.length - 1));
      }
    }
    expect(bytes.length, lessThan(3500000));
  });

  test(
    'CPU-deformed idle and aim are human-sized; death lies above the floor',
    () {
      final summary =
          jsonDecode(
                File(
                  'assets/models/characters/male_camper.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      for (final clip in ['Idle', 'Idle_Gun_Pointing', 'Gun_Shoot']) {
        final bounds = summary['checks'][clip];
        expect(bounds['min'][1] as num, inInclusiveRange(-0.01, 0.03));
        expect(bounds['max'][1] as num, inInclusiveRange(1.65, 1.9));
      }
      expect(
        summary['checks']['Death']['min'][1] as num,
        greaterThanOrEqualTo(-0.01),
      );
      expect(summary['checks']['Death']['max'][1] as num, lessThan(0.6));
    },
  );
}
