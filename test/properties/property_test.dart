import 'dart:convert';
import 'dart:io';

import 'package:crime_oren/economy/wallet.dart';
import 'package:crime_oren/properties/property.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

List<PropertyConfig> _fromAsset() {
  final json = jsonDecode(File('assets/data/properties.json').readAsStringSync()) as Map<String, dynamic>;
  return [for (final e in json['properties'] as List) PropertyConfig.fromJson(e as Map<String, dynamic>)];
}

void main() {
  test('properties.json читается: дом продаётся, вход — снаружи здания', () {
    final home = _fromAsset().single;
    expect(home.price, greaterThan(0));
    expect(home.ownedFromStart, isFalse);
    // Здание в координатах игры занимает x -6..6, z -4..10 (по высотам
    // чанков и лучом в игре) — вход вне его.
    final insideX = home.entryPoint.x > -6 && home.entryPoint.x < 6;
    final insideZ = home.entryPoint.z > -4 && home.entryPoint.z < 10;
    expect(insideX && insideZ, isFalse);
  });

  test('кнопка только у входа; без денег — не купить, с деньгами — купить', () {
    final system = PropertySystem(_fromAsset());
    final home = system.properties.single;
    final wallet = Wallet(100);
    expect(system.interactionAt(home.entryPoint + vm.Vector3(10, 0, 0), wallet), isNull);

    final poor = system.interactionAt(home.entryPoint + vm.Vector3(1, 0, 1), wallet)!;
    expect(poor.owned, isFalse);
    expect(poor.affordable, isFalse);
    expect(system.buy(home, wallet), isFalse);
    expect(wallet.balance, 100);
    expect(system.respawnPoint(), isNull);

    wallet.earn(home.price, TransactionReason.pickup);
    expect(system.interactionAt(home.entryPoint, wallet)!.affordable, isTrue);
    expect(system.buy(home, wallet), isTrue);
    expect(wallet.balance, 100);
    expect(wallet.lastTransaction!.reason, TransactionReason.purchase);
    expect(system.interactionAt(home.entryPoint, wallet)!.owned, isTrue);
    expect(system.buy(home, wallet), isFalse); // второй раз не покупается
    expect(system.respawnPoint(), home.exitPoint);
  });
}
