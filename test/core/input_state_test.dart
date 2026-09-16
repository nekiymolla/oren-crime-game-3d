import 'package:flutter_test/flutter_test.dart';
import 'package:crime_oren/core/input/input_state.dart';

void main() {
  test('consumeJump — edge-triggered: срабатывает один раз и сбрасывается', () {
    final input = InputState();

    expect(input.consumeJump(), isFalse);

    input.requestJump();
    expect(input.consumeJump(), isTrue);
    expect(input.consumeJump(), isFalse);
  });

  test('setMove сохраняет переданное направление', () {
    final input = InputState();
    input.setMove(0.5, -1.0);

    expect(input.moveDirection.x, 0.5);
    expect(input.moveDirection.y, -1.0);
  });
}
