import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crime_oren/core/game_mode.dart';
import 'package:crime_oren/core/input/input_state.dart';
import 'package:crime_oren/ui/controls/keyboard_controls.dart';

void main() {
  testWidgets(
    'driving retains full throttle in turns and Space operates the handbrake',
    (tester) async {
      gameModeState.mode = ControlMode.driving;
      inputState.jumpRequested = false;
      await tester.pumpWidget(
        MaterialApp(
          home: KeyboardControls(onInteract: () {}, child: const SizedBox()),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 17));
      expect(inputState.moveDirection.x, 1);
      expect(inputState.moveDirection.y, 1);
      expect(inputState.handbrakeHeld, isTrue);
      expect(inputState.jumpRequested, isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.pump(const Duration(milliseconds: 17));
      expect(inputState.handbrakeHeld, isFalse);
      expect(inputState.moveDirection.length, 0);
      gameModeState.mode = ControlMode.onFoot;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await tester.pump(const Duration(milliseconds: 17));
      expect(inputState.moveDirection.length, closeTo(1, .001));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.pump(const Duration(milliseconds: 17));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
