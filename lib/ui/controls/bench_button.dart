import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../engine/game.dart';

class BenchButton extends StatefulWidget {
  const BenchButton({super.key, required this.game});
  final Game game;
  @override
  State<BenchButton> createState() => _BenchButtonState();
}

class _BenchButtonState extends State<BenchButton>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  String? _label;
  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final game = widget.game;
      final label = game.benchRest.active
          ? 'Передышка · ${game.benchRest.remaining.ceil()} с'
          : game.nearbyBench != null
          ? 'Передохнуть · 5 с'
          : null;
      if (label != _label) setState(() => _label = label);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_label == null) return const SizedBox.shrink();
    return FilledButton.tonalIcon(
      onPressed: widget.game.benchRest.active
          ? widget.game.benchRest.cancel
          : widget.game.restAtBench,
      icon: Icon(widget.game.benchRest.active ? Icons.close : Icons.chair_alt),
      label: Text(_label!),
    );
  }
}
