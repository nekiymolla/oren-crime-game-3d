import 'package:flutter_test/flutter_test.dart';
import 'package:crime_oren/engine/render_resolution.dart';

void main() {
  test('Retina viewport is capped at 1920 by 1200 while UI stays native', () {
    expect(
      scenePixelRatio(
        width: 1280,
        height: 800,
        devicePixelRatio: 2,
        renderScale: 1,
      ),
      1.5,
    );
  });
  test('small viewports and reduced quality are not downscaled twice', () {
    expect(
      scenePixelRatio(
        width: 960,
        height: 600,
        devicePixelRatio: 1,
        renderScale: 1,
      ),
      1,
    );
    expect(
      scenePixelRatio(
        width: 1280,
        height: 800,
        devicePixelRatio: 2,
        renderScale: .5,
      ),
      2,
    );
  });
}
