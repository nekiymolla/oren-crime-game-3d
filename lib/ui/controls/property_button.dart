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
  bool _justSaved = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final interaction = widget.game.propertyInteraction;
      final savedAt = widget.game.lastSavedAt;
      final justSaved = savedAt != null && DateTime.now().difference(savedAt) < const Duration(seconds: 3);
      if (interaction != _interaction || justSaved != _justSaved) {
        setState(() {
          _interaction = interaction;
          _justSaved = justSaved;
        });
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    final interaction = _interaction;
    if (interaction == null) return;
    if (interaction.owned) {
      await widget.game.saveGame();
    } else {
      widget.game.buyNearbyProperty();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final interaction = _interaction;
    if (interaction == null) return const SizedBox.shrink();
    final property = interaction.property;
    final savedAt = widget.game.lastSavedAt;
    final justSaved = savedAt != null && DateTime.now().difference(savedAt) < const Duration(seconds: 3);
    final (String title, String subtitle, Color color, bool enabled) = interaction.owned
        ? interaction.canSave
              ? (
                  justSaved ? 'Сохранено ✓' : 'Сохранить игру',
                  '${property.displayName} · здесь вы появляетесь',
                  const Color(0xFF4D9BFF),
                  !justSaved,
                )
              : (property.displayName, 'Сначала оторвитесь от полиции', Colors.white38, false)
        : interaction.affordable
        ? ('Купить · ${formatRubles(property.price)} ₽', property.displayName, const Color(0xFF3DDC6E), true)
        : (
            'Не хватает ${formatRubles(property.price - widget.game.wallet.balance)} ₽',
            '${property.displayName} · ${formatRubles(property.price)} ₽',
            Colors.white38,
            false,
          );
    return GestureDetector(
      onTap: enabled ? _onTap : null,
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
