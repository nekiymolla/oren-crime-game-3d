import 'package:vector_math/vector_math.dart' as vm;

/// Лежащая на земле добыча: деньги и/или патроны. Исчезает через время.
class Pickup {
  Pickup({required this.position, required this.money, this.ammo = 0});

  final vm.Vector3 position;
  final int money;
  final int ammo;
  double ageSeconds = 0.0;
}

/// Вся добыча на земле. Чистая логика (тесты), рисует PickupsView.
/// Добычи не больше [capacity]: при переполнении пропадает самая старая.
class PickupField {
  PickupField({required this.lifetimeSeconds, required this.collectRadius, this.capacity = 16});

  final double lifetimeSeconds;
  final double collectRadius;
  final int capacity;

  final List<Pickup> items = [];

  void drop(Pickup pickup) {
    if (items.length >= capacity) items.removeAt(0);
    items.add(pickup);
  }

  /// Стареют, просроченные пропадают; всё в радиусе от [collector]
  /// подбирается и возвращается.
  List<Pickup> update(double dt, vm.Vector3? collector) {
    for (final item in items) {
      item.ageSeconds += dt;
    }
    items.removeWhere((item) => item.ageSeconds >= lifetimeSeconds);
    if (collector == null) return const [];
    final radiusSq = collectRadius * collectRadius;
    final collected = <Pickup>[];
    items.removeWhere((item) {
      final dx = item.position.x - collector.x;
      final dz = item.position.z - collector.z;
      final dy = (item.position.y - collector.y).abs();
      final take = dx * dx + dz * dz <= radiusSq && dy < 2.0;
      if (take) collected.add(item);
      return take;
    });
    return collected;
  }

  void clear() => items.clear();
}
