import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crime_oren/core/input/input_state.dart';
import 'package:crime_oren/ui/controls/keyboard_controls.dart';
import 'package:crime_oren/ui/controls/desktop_pointer_controls.dart';
import 'package:crime_oren/ui/controls/relative_pointer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    inputState.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          RelativePointer.channel,
          (call) async => call.method == 'capture' ? false : null,
        );
  });
  tearDown(inputState.reset);
  testWidgets(
    'capture click does not fire; trackpad hover looks and mouse fire remains independent',
    (tester) async {
      var movement = Offset.zero;
      Size? viewport;
      await tester.pumpWidget(
        MaterialApp(
          home: KeyboardControls(
            onInteract: () {},
            child: DesktopPointerControls(
              onLook: (delta) => movement += delta,
              onLooking: (_) {},
              onViewport: (size) => viewport = size,
              onFocus: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      expect(viewport, const Size(800, 600));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(100, 100));
      await mouse.down(const Offset(100, 100));
      await tester.pump();
      expect(inputState.fireHeld, false, reason: 'capture click must not fire');
      await mouse.up();
      await mouse.moveTo(const Offset(120, 110));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        movement.dx,
        greaterThan(0),
        reason: 'trackpad hover looks without a held button',
      );
      expect(movement.dx, lessThan(15));
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(movement.dx, closeTo(15, .001));
      expect(movement.dy, closeTo(7.5, .001));
      await mouse.down(const Offset(120, 110));
      expect(inputState.fireHeld, true);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
      await tester.pump(const Duration(milliseconds: 17));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
      await tester.pump(const Duration(milliseconds: 17));
      expect(
        inputState.fireHeld,
        true,
        reason: 'releasing F must not cancel mouse fire',
      );
      await mouse.up();
      expect(inputState.fireHeld, false);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('backgrounding clears movement, aim, fire and pending actions', (
    tester,
  ) async {
    var focusLost = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: KeyboardControls(
          onInteract: () {},
          onFocusLost: () => focusLost++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await tester.pump(const Duration(milliseconds: 17));
    expect(inputState.moveDirection.y, 1);
    inputState.mouseFireHeld = true;
    inputState.aimHeld = true;
    inputState.requestJump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 17));
    expect(inputState.moveDirection.length, 0);
    expect(inputState.fireHeld, false);
    expect(inputState.aimHeld, false);
    expect(inputState.consumeJump(), false);
    expect(focusLost, greaterThan(0));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('physical WASD works with a Cyrillic keyboard layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: KeyboardControls(
          onInteract: () {},
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    const cyrillicTse = LogicalKeyboardKey(0x0446);
    await tester.sendKeyDownEvent(
      cyrillicTse,
      physicalKey: PhysicalKeyboardKey.keyW,
      platform: 'macos',
    );
    await tester.pump(const Duration(milliseconds: 17));
    expect(inputState.moveDirection.y, 1);
    await tester.sendKeyUpEvent(
      cyrillicTse,
      physicalKey: PhysicalKeyboardKey.keyW,
      platform: 'macos',
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('paused controls ignore gameplay keys but Escape still resumes', (
    tester,
  ) async {
    var interacts = 0, pauses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: KeyboardControls(
          enabled: false,
          onInteract: () => interacts++,
          onPause: () => pauses++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(interacts, 0);
    expect(inputState.consumeJump(), false);
    expect(pauses, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
