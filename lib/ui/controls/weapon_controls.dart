import 'package:flutter/material.dart';

import '../../core/input/input_state.dart';

/// Кнопка огня: пока палец на ней — оружие стреляет с темпом из
/// weapons.json (Listener, как у RunButton: удержание, а не тап).
class FireButton extends StatelessWidget {
  const FireButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => inputState.fireHeld = true,
      onPointerUp: (_) => inputState.fireHeld = false,
      onPointerCancel: (_) => inputState.fireHeld = false,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.red.withValues(alpha: 0.28),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.8), width: 2),
        ),
        child: const Icon(Icons.gps_fixed, color: Colors.white, size: 34),
      ),
    );
  }
}

/// Перезарядка вручную (пустой магазин перезаряжается сам).
class ReloadButton extends StatelessWidget {
  const ReloadButton({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => inputState.requestReload(),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.12),
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: const Icon(Icons.autorenew, color: Colors.white70, size: 24),
      ),
    );
  }
}
