import 'package:flutter/services.dart';

/// Native relative motion is independent of the cursor reaching a screen edge.
class RelativePointer {
  static const channel = MethodChannel('crime_oren/relative_pointer');
  ValueChanged<Offset>? onDelta;
  void Function(bool primary, bool secondary)? onButtons;
  VoidCallback? onReleased;

  RelativePointer() {
    channel.setMethodCallHandler((call) async {
      final args = call.arguments;
      if (call.method == 'delta' && args is Map) {
        onDelta?.call(
          Offset(
            (args['dx'] as num).toDouble(),
            (args['dy'] as num).toDouble(),
          ),
        );
      } else if (call.method == 'buttons' && args is Map) {
        onButtons?.call(args['primary'] as bool, args['secondary'] as bool);
      } else if (call.method == 'released') {
        onReleased?.call();
      }
    });
  }
  Future<bool> capture() async {
    try {
      return await channel.invokeMethod<bool>('capture') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> release() async {
    try {
      await channel.invokeMethod<void>('release');
    } on MissingPluginException {
      /* Widget tests / unsupported desktop runner. */
    } on PlatformException {
      /* Window may already be closing. */
    }
  }

  void dispose() {
    channel.setMethodCallHandler(null);
    release();
  }
}
