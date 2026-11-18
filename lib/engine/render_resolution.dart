import 'dart:math' as math;

/// Keep the 3D render target within a pixel budget; Flutter HUD stays native.
/// The user's quality renderScale is already applied by the scene, so count
/// it here to avoid reducing low/medium presets twice.
double scenePixelRatio({
  required double width,
  required double height,
  required double devicePixelRatio,
  required double renderScale,
  double pixelBudget = 2304000,
}) {
  final pixels =
      width *
      height *
      devicePixelRatio *
      devicePixelRatio *
      renderScale *
      renderScale;
  if (pixels <= pixelBudget || pixels <= 0) return devicePixelRatio;
  return devicePixelRatio * math.sqrt(pixelBudget / pixels);
}
