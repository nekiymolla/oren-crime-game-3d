import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../engine/game.dart';
import '../../properties/property.dart';
import '../hud/money_hud.dart';

/// Кнопка у входа в дом: "Купить · 1 500 ₽", "Не хватает 300 ₽" или
/// "Ваш дом". Видна, только пока игрок у маркера (Game.propertyInteraction
/// опрашивается своим Ticker'ом, как VehicleInteractButton).
class PropertyButton extends StatefulWidget {
  const PropertyButton({super.key, required this.game});

  final Game game;

  @override
  State<PropertyButton> createState() => _PropertyButtonState();
}

class _PropertyButtonState extends State<PropertyButton> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  PropertyInteraction? _interaction;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final interaction = widget.game.propertyInteraction;
      if (interaction != _interaction) setState(() => _interaction = interaction);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final interaction = _interaction;
    if (interaction == null) return const SizedBox.shrink();
    final property = interaction.property;
    final (String title, String subtitle, Color color, bool enabled) = interaction.owned
        ? (property.displayName, 'Ваш дом · здесь вы появляетесь', const Color(0xFF4D9BFF), false)
        : interaction.affordable
        ? ('Купить · ${formatRubles(property.price)} ₽', property.displayName, const Color(0xFF3DDC6E), true)
        : (
            'Не хватает ${formatRubles(property.price - widget.game.wallet.balance)} ₽',
            '${property.displayName} · ${formatRubles(property.price)} ₽',
            Colors.white38,
            false,
          );
    return GestureDetector(
      onTap: enabled ? () => setState(() => widget.game.buyNearbyProperty()) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
