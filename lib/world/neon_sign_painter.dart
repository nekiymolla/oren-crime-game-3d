import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Текстура неоновой вывески: надпись (и у части вывесок — рамка) рисуется
/// тремя слоями, как светится настоящая неонка: широкий размытый ореол,
/// цветная трубка и почти белая сердцевина. Фон прозрачный.
///
/// Рисуется в рантайме через Canvas, а не лежит картинками в ассетах:
/// надписи и цвета берутся из данных, и новая вывеска не требует рисовать
/// новый файл.
Future<ui.Image> paintNeonSign(String text, Color color, {bool framed = false}) async {
  const width = 512.0;
  const height = 128.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  // Подбор кегля: надпись помещается в рамку с полями.
  const maxTextWidth = width - 70.0;
  const maxTextHeight = height - 44.0;
  final probe = _layout(text, 100, Paint());
  final fontSize = 100 * math.min<double>(maxTextWidth / probe.width, maxTextHeight / probe.height);

  final core = Color.lerp(color, const Color(0xFFFFFFFF), 0.75)!;
  final layers = [
    Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round,
    Paint()
      ..color = core
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round,
  ];

  final frame = RRect.fromRectAndRadius(
    const Rect.fromLTWH(12, 12, width - 24, height - 24),
    const Radius.circular(16),
  );
  for (final paint in layers) {
    if (framed) canvas.drawRRect(frame, paint);
    final painter = _layout(text, fontSize, paint);
    painter.paint(canvas, Offset((width - painter.width) / 2, (height - painter.height) / 2));
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(width.toInt(), height.toInt());
  picture.dispose();
  return image;
}

TextPainter _layout(String text, double fontSize, Paint foreground) => TextPainter(
  text: TextSpan(
    text: text,
    style: TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: fontSize * 0.08,
      foreground: foreground,
    ),
  ),
  textDirection: TextDirection.ltr,
  maxLines: 1,
)..layout();
