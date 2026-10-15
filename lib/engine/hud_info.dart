/// Что показывать на радаре и компасе HUD — метки мира в мировых XZ.
/// Отдельно от виджетов, чтобы Game (чистый Dart) мог их собирать, не
/// импортируя Flutter.
enum BlipKind { houseForSale, houseOwned, policeCar, officer, money, ammo, armor }

class HudBlip {
  const HudBlip(this.kind, this.x, this.z);

  final BlipKind kind;
  final double x;
  final double z;
}
