import 'package:vector_math/vector_math.dart' as vm;

/// Снимок прогресса игрока (ТЗ, раздел 24). Формат версионный: [version]
/// пишется в файл, а [SaveData.fromJson] переводит старые версии в
/// текущую (см. [migrateSave]) — структуру можно менять, не теряя старые
/// сохранения. Чистые данные без Flutter — проверены тестами.
class SaveData {
  const SaveData({
    required this.money,
    required this.ownedProperties,
    required this.position,
    required this.yaw,
    required this.health,
    this.armor = 0.0,
    required this.weaponId,
    required this.ammoInMagazine,
    required this.reserveAmmo,
    required this.clockHours,
    required this.dayOfYear,
    required this.weather,
    required this.qualityPreset,
  });

  /// Текущая версия формата. Поднимать при изменении полей и добавлять
  /// шаг в [migrateSave].
  ///
  /// v2 (15.10.2026): бронежилет `player.armor`.
  static const int currentVersion = 2;

  final int money;
  final List<String> ownedProperties;
  final vm.Vector3 position;
  final double yaw;
  final double health;
  final double armor;
  final String weaponId;
  final int ammoInMagazine;
  final int reserveAmmo;
  final double clockHours;
  final int dayOfYear;

  /// Имя WeatherKind.
  final String weather;

  /// Настройки: имя пресета качества.
  final String qualityPreset;

  Map<String, dynamic> toJson() => {
    'version': currentVersion,
    'savedAt': DateTime.now().toUtc().toIso8601String(),
    'player': {
      'position': [position.x, position.y, position.z],
      'yaw': yaw,
      'health': health,
      'armor': armor,
    },
    'money': money,
    'properties': ownedProperties,
    'weapons': [
      {'id': weaponId, 'ammoInMagazine': ammoInMagazine, 'reserveAmmo': reserveAmmo},
    ],
    'world': {'clockHours': clockHours, 'dayOfYear': dayOfYear, 'weather': weather},
    'settings': {'qualityPreset': qualityPreset},
  };

  /// null — файл не того формата или из будущей версии игры.
  static SaveData? fromJson(Map<String, dynamic> raw) {
    final json = migrateSave(raw);
    if (json == null) return null;
    final player = json['player'] as Map<String, dynamic>;
    final position = (player['position'] as List).cast<num>();
    final weapon = (json['weapons'] as List).first as Map<String, dynamic>;
    final world = json['world'] as Map<String, dynamic>;
    final settings = json['settings'] as Map<String, dynamic>;
    return SaveData(
      money: json['money'] as int,
      ownedProperties: (json['properties'] as List).cast<String>(),
      position: vm.Vector3(position[0].toDouble(), position[1].toDouble(), position[2].toDouble()),
      yaw: (player['yaw'] as num).toDouble(),
      health: (player['health'] as num).toDouble(),
      armor: (player['armor'] as num).toDouble(),
      weaponId: weapon['id'] as String,
      ammoInMagazine: weapon['ammoInMagazine'] as int,
      reserveAmmo: weapon['reserveAmmo'] as int,
      clockHours: (world['clockHours'] as num).toDouble(),
      dayOfYear: world['dayOfYear'] as int,
      weather: world['weather'] as String,
      qualityPreset: settings['qualityPreset'] as String,
    );
  }
}

/// Приводит сохранение любой известной версии к [SaveData.currentVersion]
/// по шагу за раз. Неизвестная (будущая) версия — null: такое
/// сохранение не трогаем.
Map<String, dynamic>? migrateSave(Map<String, dynamic> json) {
  var version = json['version'];
  if (version is! int || version < 1 || version > SaveData.currentVersion) return null;
  final migrated = Map<String, dynamic>.of(json);
  if (version == 1) {
    // v1 -> v2: бронежилета ещё не было.
    final player = Map<String, dynamic>.of(migrated['player'] as Map<String, dynamic>);
    player['armor'] = 0.0;
    migrated['player'] = player;
    version = 2;
  }
  migrated['version'] = version;
  return migrated;
}
