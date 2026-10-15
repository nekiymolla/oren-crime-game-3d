import 'dart:convert';
import 'dart:io';

import 'package:crime_oren/economy/wallet.dart';
import 'package:crime_oren/properties/property.dart';
import 'package:crime_oren/save/save_data.dart';
import 'package:crime_oren/save/save_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

SaveData _sample() => SaveData(
  money: 1234,
  ownedProperties: const ['home_player_01'],
  position: vm.Vector3(9.5, 0, -2),
  yaw: 1.25,
  health: 73.5,
  weaponId: 'pistol_makarov',
  ammoInMagazine: 5,
  reserveAmmo: 40,
  clockHours: 21.5,
  dayOfYear: 290,
  weather: 'rain',
  qualityPreset: 'medium',
);

void main() {
  test('сохранение переживает JSON туда и обратно, версия пишется', () {
    final json = jsonDecode(jsonEncode(_sample().toJson())) as Map<String, dynamic>;
    expect(json['version'], SaveData.currentVersion);
    final back = SaveData.fromJson(json)!;
    expect(back.money, 1234);
    expect(back.ownedProperties, ['home_player_01']);
    expect(back.position, vm.Vector3(9.5, 0, -2));
    expect(back.yaw, 1.25);
    expect(back.health, 73.5);
    expect(back.ammoInMagazine, 5);
    expect(back.reserveAmmo, 40);
    expect(back.clockHours, 21.5);
    expect(back.dayOfYear, 290);
    expect(back.weather, 'rain');
    expect(back.qualityPreset, 'medium');
  });

  test('сохранение из будущей версии и без версии не читается', () {
    final json = _sample().toJson();
    expect(SaveData.fromJson({...json, 'version': SaveData.currentVersion + 1}), isNull);
    expect(SaveData.fromJson({...json}..remove('version')), isNull);
  });

  test('запись на диск и чтение; битый файл — как будто сохранения нет', () async {
    final dir = await Directory.systemTemp.createTemp('crime_oren_save_test');
    addTearDown(() => dir.delete(recursive: true));
    final store = SaveStore(directory: () async => dir);
    expect(await store.read(), isNull);
    await store.write(_sample());
    expect((await store.read())!.money, 1234);
    expect(File('${dir.path}/${SaveStore.fileName}.tmp').existsSync(), isFalse);

    File('${dir.path}/${SaveStore.fileName}').writeAsStringSync('{не json');
    expect(await store.read(), isNull);
  });

  test('баланс из сохранения — без операции в истории', () {
    final wallet = Wallet(300)..earn(50, TransactionReason.pickup);
    final revision = wallet.revision;
    wallet.restore(1234);
    expect(wallet.balance, 1234);
    expect(wallet.history, isEmpty);
    expect(wallet.revision, greaterThan(revision));
  });

  test('сохраниться можно только у своего дома и без розыска', () {
    final home = PropertyConfig(
      id: 'h',
      displayName: 'дом',
      price: 10,
      entryPoint: vm.Vector3.zero(),
      exitPoint: vm.Vector3.zero(),
      isSaveSpot: true,
    );
    final system = PropertySystem([home]);
    final wallet = Wallet(100);
    expect(system.interactionAt(vm.Vector3.zero(), wallet)!.canSave, isFalse); // не куплен
    system.buy(home, wallet);
    expect(system.interactionAt(vm.Vector3.zero(), wallet)!.canSave, isTrue);
    expect(system.interactionAt(vm.Vector3.zero(), wallet, wanted: true)!.canSave, isFalse);
  });
}
