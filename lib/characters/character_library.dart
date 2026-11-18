import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_scene/scene.dart';

import 'character_model.dart';

/// Кто кем выглядит — assets/data/characters.json.
class CharacterRoster {
  const CharacterRoster({
    required this.player,
    required this.police,
    required this.civilians,
    required this.animationCarriers,
    this.modelAnimationCarriers = const {},
  });

  factory CharacterRoster.fromJson(Map<String, dynamic> json) =>
      CharacterRoster(
        player: json['player'] as String,
        police: (json['police'] as List).cast<String>(),
        civilians: (json['civilians'] as List).cast<String>(),
        animationCarriers: (json['animationCarriers'] as Map)
            .cast<String, String>(),
        modelAnimationCarriers:
            (json['modelAnimationCarriers'] as Map? ?? const {})
                .cast<String, String>(),
      );

  final String player;
  final List<String> police;
  final List<String> civilians;

  /// Пол -> модель, в которой лежат клипы (у остальных анимации вырезаны).
  final Map<String, String> animationCarriers;

  /// Models with a different skeleton must use their own animation library.
  final Map<String, String> modelAnimationCarriers;

  Set<String> get allIds => {
    player,
    ...police,
    ...civilians,
    ...animationCarriers.values,
    ...modelAnimationCarriers.values,
  };

  String animationCarrierFor(String id) =>
      modelAnimationCarriers[id] ?? animationCarriers[genderOf(id)] ?? id;

  /// Пол модели — по префиксу id (male_*/female_*).
  static String genderOf(String id) =>
      id.startsWith('female_') ? 'female' : 'male';
}

/// Загруженные шаблоны моделей персонажей. Каждый шаблон грузится один
/// раз; [create] клонирует его (геометрия и материал общие, скелет и
/// анимация — свои у каждого клона).
class CharacterLibrary {
  CharacterLibrary._(this.roster, this._templates);

  static const String modelsDir = 'assets/models/characters';

  final CharacterRoster roster;
  final Map<String, Node> _templates;

  static Future<CharacterLibrary> load() async {
    final raw = await rootBundle.loadString('assets/data/characters.json');
    final roster = CharacterRoster.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    final ids = roster.allIds.toList();
    final nodes = await Future.wait(
      ids.map((id) => loadScene('$modelsDir/$id.glb')),
    );
    return CharacterLibrary._(roster, {
      for (var i = 0; i < ids.length; i++) ids[i]: nodes[i],
    });
  }

  /// Новый персонаж в облике [id].
  CharacterModel create(String id) {
    final resolvedId = _templates.containsKey(id) ? id : roster.player;
    final template = _templates[resolvedId]!;
    final carrierId = roster.animationCarrierFor(resolvedId);
    final carrier = _templates[carrierId] ?? template;
    return CharacterModel(template.clone(), carrier.parsedAnimations);
  }

  /// Случайный прохожий.
  CharacterModel createCivilian(math.Random random) =>
      create(roster.civilians[random.nextInt(roster.civilians.length)]);

  /// Случайный полицейский.
  CharacterModel createOfficer(math.Random random) =>
      create(roster.police[random.nextInt(roster.police.length)]);
}
