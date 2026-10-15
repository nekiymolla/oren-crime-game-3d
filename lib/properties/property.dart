import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:vector_math/vector_math.dart' as vm;

import '../economy/wallet.dart';

/// Объект недвижимости из assets/data/properties.json (ТЗ, раздел 18).
/// Читаются поля, которые нужны сейчас: цена, вход, точка выхода
/// (возрождение), точка сохранения. Интерьер и гараж — позже.
class PropertyConfig {
  const PropertyConfig({
    required this.id,
    required this.displayName,
    required this.price,
    required this.entryPoint,
    required this.exitPoint,
    this.ownedFromStart = false,
    this.isSaveSpot = false,
  });

  factory PropertyConfig.fromJson(Map<String, dynamic> json) {
    vm.Vector3 point(String key) {
      final list = (json[key] as List).cast<num>();
      return vm.Vector3(list[0].toDouble(), list[1].toDouble(), list[2].toDouble());
    }

    return PropertyConfig(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      price: (json['price'] as num).round(),
      entryPoint: point('entryPointLocal'),
      exitPoint: point('exitPointLocal'),
      ownedFromStart: json['owned'] as bool? ?? false,
      isSaveSpot: json['isSaveSpot'] as bool? ?? false,
    );
  }

  final String id;
  final String displayName;
  final int price;

  /// Где стоит маркер и откуда доступна покупка.
  final vm.Vector3 entryPoint;

  /// Где игрок появляется у своего дома (после смерти, ареста).
  final vm.Vector3 exitPoint;
  final bool ownedFromStart;
  final bool isSaveSpot;
}

Future<List<PropertyConfig>> loadProperties() async {
  final raw = await rootBundle.loadString('assets/data/properties.json');
  final json = jsonDecode(raw) as Map<String, dynamic>;
  return [
    for (final entry in json['properties'] as List) PropertyConfig.fromJson(entry as Map<String, dynamic>),
  ];
}

/// Что можно сделать у входа в дом — для кнопки в HUD.
class PropertyInteraction {
  const PropertyInteraction({
    required this.property,
    required this.owned,
    required this.affordable,
    this.canSave = false,
  });

  final PropertyConfig property;
  final bool owned;
  final bool affordable;

  /// Свой дом с точкой сохранения и нет розыска — можно сохраниться.
  final bool canSave;

  @override
  bool operator ==(Object other) =>
      other is PropertyInteraction &&
      other.property.id == property.id &&
      other.owned == owned &&
      other.affordable == affordable &&
      other.canSave == canSave;

  @override
  int get hashCode => Object.hash(property.id, owned, affordable, canSave);
}

/// Недвижимость игрока: что есть в мире, что куплено. Чистая логика
/// (проверена тестами).
class PropertySystem {
  PropertySystem(this.properties) : owned = {for (final p in properties) if (p.ownedFromStart) p.id};

  final List<PropertyConfig> properties;
  final Set<String> owned;

  /// На каком расстоянии от входа доступна кнопка.
  static const double interactRadius = 2.5;

  bool isOwned(PropertyConfig property) => owned.contains(property.id);

  /// Вход в пределах [interactRadius] от [position] (по плоскости).
  /// [wanted] — идёт розыск: сохраняться нельзя, как в GTA.
  PropertyInteraction? interactionAt(vm.Vector3 position, Wallet wallet, {bool wanted = false}) {
    for (final property in properties) {
      final dx = property.entryPoint.x - position.x;
      final dz = property.entryPoint.z - position.z;
      if (dx * dx + dz * dz > interactRadius * interactRadius) continue;
      final isOwned = owned.contains(property.id);
      return PropertyInteraction(
        property: property,
        owned: isOwned,
        affordable: isOwned || wallet.balance >= property.price,
        canSave: isOwned && property.isSaveSpot && !wanted,
      );
    }
    return null;
  }

  /// Купить: списывает цену, если хватает. true — дом теперь свой.
  bool buy(PropertyConfig property, Wallet wallet) {
    if (isOwned(property)) return false;
    if (!wallet.spend(property.price, TransactionReason.purchase)) return false;
    owned.add(property.id);
    return true;
  }

  /// Где возрождаться: у первого своего дома, иначе null (точка спавна).
  vm.Vector3? respawnPoint() {
    for (final property in properties) {
      if (owned.contains(property.id)) return property.exitPoint.clone();
    }
    return null;
  }
}
