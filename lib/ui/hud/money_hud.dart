import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../economy/wallet.dart';

/// Баланс "₽ 1 250" и всплывающая последняя операция ("+₽120 подобрано",
/// "−₽180 больница") на пару секунд. Опрашивает [Wallet.revision] своим
/// Ticker'ом, как WantedStars.
class MoneyHud extends StatefulWidget {
  const MoneyHud({super.key, required this.wallet});

  final Wallet wallet;

  @override
  State<MoneyHud> createState() => _MoneyHudState();
}

class _MoneyHudState extends State<MoneyHud> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late int _revision = widget.wallet.revision;
  late int _balance = widget.wallet.balance;
  Transaction? _shown;
  Duration _shownAt = Duration.zero;
  Duration _now = Duration.zero;

  static const Duration _popupDuration = Duration(milliseconds: 2500);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _now = elapsed;
      final wallet = widget.wallet;
      if (wallet.revision != _revision) {
        setState(() {
          _revision = wallet.revision;
          _balance = wallet.balance;
          _shown = wallet.lastTransaction;
          _shownAt = elapsed;
        });
      } else if (_shown != null && elapsed - _shownAt > _popupDuration) {
        setState(() => _shown = null);
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(blurRadius: 3, color: Colors.black)];
    final shown = _shown;
    final fade = shown == null ? 0.0 : (1.0 - (_now - _shownAt).inMilliseconds / _popupDuration.inMilliseconds).clamp(0.0, 1.0);
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '₽ ${formatRubles(_balance)}',
            style: const TextStyle(color: Color(0xFF7CFC9A), fontSize: 18, fontWeight: FontWeight.w700, shadows: shadow),
          ),
          if (shown != null)
            Opacity(
              opacity: fade,
              child: Text(
                '${shown.amount > 0 ? '+' : '−'}₽${formatRubles(shown.amount.abs())} ${shown.reason.label}',
                style: TextStyle(
                  color: shown.amount > 0 ? const Color(0xFF7CFC9A) : const Color(0xFFFF6B6B),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  shadows: shadow,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 1250 -> "1 250" (тонкий пробел между тысячами, как пишут рубли).
String formatRubles(int amount) {
  final digits = amount.abs().toString();
  final buffer = StringBuffer(amount < 0 ? '−' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
