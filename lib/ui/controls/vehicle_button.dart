import 'package:flutter/material.dart';

/// Кнопка "сесть/выйти из машины". Сама ничего не решает — просто дёргает
/// переданный колбэк (Game.toggleVehicle), который сам проверяет дистанцию.
class VehicleButton extends StatelessWidget {
  const VehicleButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.12),
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: const Icon(Icons.directions_car, color: Colors.white70),
      ),
    );
  }
}
