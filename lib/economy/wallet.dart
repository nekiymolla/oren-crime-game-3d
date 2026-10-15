import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

/// Почему изменились деньги — для истории и всплывающих подсказок в HUD.
enum TransactionReason {
  pickup('подобрано'),
  hospital('больница'),
  arrestFine('штраф'),
  purchase('покупка');

  const TransactionReason(this.label);

  final String label;
}

/// Одна операция с деньгами: [amount] со знаком (+ доход, − расход).
class Transaction {
  const Transaction(this.amount, this.reason);

  final int amount;
  final TransactionReason reason;
}

/// Кошелёк игрока (ТЗ, раздел 17). Чистая логика без Flutter — проверена
/// тестами. Покупка без денег не проходит ([spend] → false), а штраф
/// ([charge]) забирает сколько есть — в минус баланс не уходит.
class Wallet {
  Wallet([this._balance = 0]);

  int _balance;
  int get balance => _balance;

  /// Последние операции, новые в конце (не больше [historyLimit]).
  final List<Transaction> history = [];
  static const int historyLimit = 50;

  /// Растёт с каждой операцией — HUD по нему замечает новую.
  int revision = 0;

  Transaction? get lastTransaction => history.isEmpty ? null : history.last;

  /// Загрузка сохранения: баланс как был, без операции в истории.
  void restore(int balance) {
    _balance = math.max(0, balance);
    history.clear();
    revision++;
  }

  void earn(int amount, TransactionReason reason) {
    if (amount <= 0) return;
    _balance += amount;
    _record(Transaction(amount, reason));
  }

  /// Покупка: true и списание, если хватает; иначе ничего не меняется.
  bool spend(int amount, TransactionReason reason) {
    if (amount <= 0) return true;
    if (amount > _balance) return false;
    _balance -= amount;
    _record(Transaction(-amount, reason));
    return true;
  }

  /// Штраф: списывает сколько есть, не больше [amount]. Возвращает
  /// фактически списанное.
  int charge(int amount, TransactionReason reason) {
    final taken = math.min(math.max(0, amount), _balance);
    if (taken == 0) return 0;
    _balance -= taken;
    _record(Transaction(-taken, reason));
    return taken;
  }

  void _record(Transaction transaction) {
    history.add(transaction);
    if (history.length > historyLimit) history.removeAt(0);
    revision++;
  }
}

/// Штраф вида "база + процент от баланса" (больница, арест).
class Penalty {
  const Penalty({required this.base, required this.percent});

  factory Penalty.fromJson(Map<String, dynamic> json) =>
      Penalty(base: json['base'] as int, percent: (json['percent'] as num).toDouble());

  final int base;
  final double percent;

  int amountFor(int balance) => base + (balance * percent).round();
}

/// Сколько выпадает с убитого: случайно в [min]..[max] рублей и [ammo]
/// патронов.
class Drop {
  const Drop({required this.min, required this.max, this.ammo = 0});

  factory Drop.fromJson(Map<String, dynamic> json) =>
      Drop(min: json['min'] as int, max: json['max'] as int, ammo: json['ammo'] as int? ?? 0);

  final int min;
  final int max;
  final int ammo;

  int rollMoney(math.Random random) => min + random.nextInt(max - min + 1);
}

/// Числа экономики из assets/data/economy.json.
class EconomyConfig {
  const EconomyConfig({
    required this.startingMoney,
    required this.hospital,
    required this.arrest,
    required this.pedestrianDrop,
    required this.officerDrop,
    required this.pickupLifetimeSeconds,
    required this.pickupRadius,
  });

  factory EconomyConfig.fromJson(Map<String, dynamic> json) => EconomyConfig(
    startingMoney: json['startingMoney'] as int,
    hospital: Penalty.fromJson(json['hospital'] as Map<String, dynamic>),
    arrest: Penalty.fromJson(json['arrest'] as Map<String, dynamic>),
    pedestrianDrop: Drop.fromJson(json['pedestrianDrop'] as Map<String, dynamic>),
    officerDrop: Drop.fromJson(json['officerDrop'] as Map<String, dynamic>),
    pickupLifetimeSeconds: (json['pickupLifetimeSeconds'] as num).toDouble(),
    pickupRadius: (json['pickupRadius'] as num).toDouble(),
  );

  final int startingMoney;
  final Penalty hospital;
  final Penalty arrest;
  final Drop pedestrianDrop;
  final Drop officerDrop;
  final double pickupLifetimeSeconds;
  final double pickupRadius;
}

Future<EconomyConfig> loadEconomyConfig() async {
  final raw = await rootBundle.loadString('assets/data/economy.json');
  return EconomyConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
