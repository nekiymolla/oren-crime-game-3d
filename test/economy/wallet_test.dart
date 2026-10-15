import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crime_oren/economy/pickups.dart';
import 'package:crime_oren/economy/wallet.dart';
import 'package:crime_oren/ui/hud/money_hud.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' as vm;

void main() {
  test('доход, покупка, отказ без денег', () {
    final wallet = Wallet(100);
    wallet.earn(50, TransactionReason.pickup);
    expect(wallet.balance, 150);
    expect(wallet.spend(200, TransactionReason.purchase), isFalse);
    expect(wallet.balance, 150);
    expect(wallet.spend(120, TransactionReason.purchase), isTrue);
    expect(wallet.balance, 30);
    expect(wallet.history.map((t) => t.amount), [50, -120]);
    expect(wallet.lastTransaction!.reason, TransactionReason.purchase);
  });

  test('штраф забирает сколько есть, в минус не уходит', () {
    final wallet = Wallet(80);
    final revision = wallet.revision;
    expect(wallet.charge(150, TransactionReason.hospital), 80);
    expect(wallet.balance, 0);
    expect(wallet.revision, greaterThan(revision));
    // Нечего брать — операции нет.
    expect(wallet.charge(150, TransactionReason.hospital), 0);
    expect(wallet.history.length, 1);
  });

  test('история не растёт бесконечно', () {
    final wallet = Wallet();
    for (var i = 0; i < Wallet.historyLimit + 10; i++) {
      wallet.earn(1, TransactionReason.pickup);
    }
    expect(wallet.history.length, Wallet.historyLimit);
  });

  test('economy.json читается; больница и штраф — база плюс процент', () {
    final config = EconomyConfig.fromJson(jsonDecode(File('assets/data/economy.json').readAsStringSync()) as Map<String, dynamic>);
    expect(config.startingMoney, greaterThan(0));
    expect(config.hospital.amountFor(1000), config.hospital.base + (1000 * config.hospital.percent).round());
    expect(config.officerDrop.ammo, greaterThan(0));
    final random = Random(1);
    for (var i = 0; i < 200; i++) {
      final money = config.pedestrianDrop.rollMoney(random);
      expect(money, inInclusiveRange(config.pedestrianDrop.min, config.pedestrianDrop.max));
    }
  });

  test('добыча подбирается рядом, исчезает со временем, старая вытесняется', () {
    final field = PickupField(lifetimeSeconds: 10, collectRadius: 1.5, capacity: 2);
    field.drop(Pickup(position: vm.Vector3(0, 0, 0), money: 10));
    field.drop(Pickup(position: vm.Vector3(5, 0, 0), money: 20));
    field.drop(Pickup(position: vm.Vector3(9, 0, 0), money: 30)); // вытесняет первую
    expect(field.items.map((p) => p.money), [20, 30]);

    expect(field.update(1, vm.Vector3(0, 0, 0)), isEmpty);
    final taken = field.update(1, vm.Vector3(5.5, 0, 0.5));
    expect(taken.single.money, 20);
    expect(field.update(1, null), isEmpty); // мёртвый не подбирает
    field.update(10, null);
    expect(field.items, isEmpty);
  });

  test('рубли с разделителем тысяч', () {
    expect(formatRubles(0), '0');
    expect(formatRubles(950), '950');
    expect(formatRubles(1250), '1 250');
    expect(formatRubles(1000000), '1 000 000');
  });
}
