import 'package:flutter/material.dart';

import '../game.dart';

/// Debug-панель для замеров производительности прямо на устройстве: верхняя
/// строка переключает пресет качества целиком (см. assets/data/quality.json),
/// нижняя — отдельно [Scene.renderScale] поверх текущего пресета.
///
/// Две ручки, а не одна, потому что у них разные задачи при профилировании:
/// пресет даёт общий замер "как игра пойдёт на этом железе", а renderScale
/// проверяет ОДИН фактор изолированно — без этого нельзя понять, что именно
/// дало выигрыш, а на угадывании в этом проекте уже теряли раунд (мерж мешей
/// сделал FPS хуже, см. PROGRESS.md).
///
/// Обе строки в одном виджете с общим setState: пресет перезаписывает
/// renderScale, и будь это два отдельных виджета, нижняя строка показывала бы
/// значение, которого в сцене уже нет.
///
/// Население пешеходов и потолок деревьев кнопкой не меняются — это состав
/// уже созданных систем, он фиксируется при старте (см. Game.applyQuality).
class QualityDebugPanel extends StatefulWidget {
  const QualityDebugPanel({super.key, required this.game});

  final Game game;

  @override
  State<QualityDebugPanel> createState() => _QualityDebugPanelState();
}

class _QualityDebugPanelState extends State<QualityDebugPanel> {
  static const List<double> _scaleSteps = [1.0, 0.75, 0.5];

  void _cyclePreset() {
    final ordered = widget.game.qualityPresets.ordered;
    if (ordered.isEmpty) return;
    final current = ordered.indexWhere((preset) => preset.name == widget.game.quality.name);
    setState(() => widget.game.applyQuality(ordered[(current + 1) % ordered.length]));
  }

  void _cycleScale() {
    final current = widget.game.scene.renderScale;
    // indexWhere вернёт -1, если сцена стоит на значении не из списка (его
    // мог выставить пресет) — тогда (-1 + 1) % len == 0, начинаем сначала.
    final index = _scaleSteps.indexWhere((step) => (step - current).abs() < 0.001);
    setState(() => widget.game.scene.renderScale = _scaleSteps[(index + 1) % _scaleSteps.length]);
  }

  void _toggleShadows() {
    final quality = widget.game.quality;
    setState(
      () => widget.game.applyQuality(quality.copyWith(shadowsEnabled: !quality.shadowsEnabled)),
    );
  }

  void _toggleAmbientOcclusion() {
    final quality = widget.game.quality;
    setState(
      () => widget.game.applyQuality(
        quality.copyWith(ambientOcclusionEnabled: !quality.ambientOcclusionEnabled),
      ),
    );
  }

  void _toggleBloom() {
    final quality = widget.game.quality;
    setState(() => widget.game.applyQuality(quality.copyWith(bloomEnabled: !quality.bloomEnabled)));
  }

  void _cycleShadowMap() {
    final quality = widget.game.quality;
    final next = quality.shadowMapResolution > 512 ? 512 : 1024;
    setState(() => widget.game.applyQuality(quality.copyWith(shadowMapResolution: next)));
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final quality = game.quality;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        _row('preset: ${quality.name}', _cyclePreset),
        _row('scale ${game.scene.renderScale.toStringAsFixed(2)}', _cycleScale),
        _row('shadows ${_onOff(quality.shadowsEnabled)}', _toggleShadows),
        _row('shadowMap ${quality.shadowMapResolution}', _cycleShadowMap),
        _row('AO ${_onOff(quality.ambientOcclusionEnabled)}', _toggleAmbientOcclusion),
        _row('bloom ${_onOff(quality.bloomEnabled)}', _toggleBloom),
        _row('ground ${_onOff(game.groundVisible)}', () {
          setState(() => game.groundVisible = !game.groundVisible);
        }),
        _row('trees ${_onOff(game.vegetationVisible)}', () {
          setState(() => game.vegetationVisible = !game.vegetationVisible);
        }),
        _row('rays ${_onOff(game.obstacleAvoidance)}', () {
          setState(() => game.obstacleAvoidance = !game.obstacleAvoidance);
        }),
        // Дорожный граф: жёлтый — трафик, серый — дворовые проезды, голубой
        // — пешеходные дорожки (см. Game.roadGraphDebugVisible).
        _row('graph ${_onOff(game.roadGraphDebugVisible)}', () {
          setState(() => game.roadGraphDebugVisible = !game.roadGraphDebugVisible);
        }),
        // Перемотка времени — посмотреть закат/ночь, не ожидая минутами.
        _row('time +1h', () {
          setState(() => game.clock.advance(60 * 60 / game.clock.gameMinutesPerSecond));
        }),
      ],
    );
  }

  static String _onOff(bool value) => value ? 'on' : 'off';

  Widget _row(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        color: const Color(0xAA000000),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF00FF66),
            fontSize: 12,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
