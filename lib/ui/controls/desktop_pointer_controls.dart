import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'pointer_look_filter.dart';

import '../../core/input/input_state.dart';
import 'relative_pointer.dart';

/// Click the world to capture; the first click never fires. Relative motion
/// works with a mouse or trackpad without holding a secondary button.
class DesktopPointerControls extends StatefulWidget {
  const DesktopPointerControls({
    super.key,
    required this.onLook,
    required this.onLooking,
    required this.onFocus,
    this.enabled = true,
    this.onViewport,
  });
  final ValueChanged<Offset> onLook;
  final ValueChanged<bool> onLooking;
  final VoidCallback onFocus;
  final bool enabled;
  final ValueChanged<Size>? onViewport;
  @override
  State<DesktopPointerControls> createState() => _DesktopPointerControlsState();
}

class _DesktopPointerControlsState extends State<DesktopPointerControls>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _lookTicker;
  final _lookFilter = PointerLookFilter();
  Duration? _lastLookFrame;
  late final RelativePointer _pointer;
  bool _captured = false, _native = false, _requesting = false;
  int _captureEpoch = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lookTicker = createTicker((elapsed) {
      final dt = _lastLookFrame == null
          ? 1 / 60
          : (elapsed - _lastLookFrame!).inMicroseconds / 1e6;
      _lastLookFrame = elapsed;
      if (!_captured || !widget.enabled) {
        _lookFilter.clear();
        return;
      }
      final delta = _lookFilter.step(dt.clamp(0.0, .05));
      if (delta.distanceSquared > 0) widget.onLook(delta);
    })..start();
    _pointer = RelativePointer()
      ..onDelta = (delta) {
        if (_captured && widget.enabled) _lookFilter.add(delta);
      }
      ..onButtons = (primary, secondary) {
        if (_captured && widget.enabled) _buttons(primary, secondary);
      }
      ..onReleased = () => _release(notifyNative: false);
  }

  void _buttons(bool primary, bool secondary) {
    inputState.mouseFireHeld = primary;
    inputState.aimHeld = secondary;
  }

  Future<void> _capture() async {
    if (!widget.enabled || _requesting || _captured) return;
    widget.onFocus();
    final epoch = _captureEpoch;
    _requesting = true;
    final native = await _pointer.capture();
    _requesting = false;
    if (!mounted || !widget.enabled || epoch != _captureEpoch) {
      await _pointer.release();
      return;
    }
    setState(() {
      _captured = true;
      _native = native;
    });
    widget.onLooking(true);
  }

  void _release({bool notifyNative = true}) {
    _captureEpoch++;
    _lookFilter.clear();
    inputState.mouseFireHeld = false;
    inputState.aimHeld = false;
    if (notifyNative) _pointer.release();
    if (_captured) {
      if (mounted) {
        setState(() => _captured = false);
      } else {
        _captured = false;
      }
    }
    widget.onLooking(false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _release();
  }

  @override
  void didUpdateWidget(DesktopPointerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _release();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lookTicker.dispose();
    _pointer.dispose();
    inputState.mouseFireHeld = false;
    inputState.aimHeld = false;
    super.dispose();
  }

  void _eventButtons(PointerEvent e) {
    if (_captured && widget.enabled && e.kind == PointerDeviceKind.mouse) {
      _buttons(
        e.buttons & kPrimaryMouseButton != 0,
        e.buttons & kSecondaryMouseButton != 0,
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      widget.onViewport?.call(constraints.biggest);
      return MouseRegion(
        cursor: _captured ? SystemMouseCursors.none : SystemMouseCursors.click,
        onHover: (e) {
          if (_captured && !_native && widget.enabled) _lookFilter.add(e.delta);
        },
        onExit: (_) {
          if (!_native) _release();
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (!_captured) {
              _capture();
            } else {
              _eventButtons(e);
            }
          },
          onPointerUp: _eventButtons,
          onPointerCancel: (_) => _release(),
          onPointerMove: (e) {
            _eventButtons(e);
            if (_captured && !_native && widget.enabled) {
              _lookFilter.add(e.delta);
            }
          },
          child: Stack(
            children: [
              const SizedBox.expand(),
              if (!_captured && widget.enabled)
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 100,
                  child: IgnorePointer(
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Text(
                            'Нажми на сцену · мышь / тачпад — камера',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
