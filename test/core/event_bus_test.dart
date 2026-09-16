import 'package:flutter_test/flutter_test.dart';
import 'package:crime_oren/core/event_bus.dart';

class _TestEvent extends GameEvent {
  const _TestEvent(this.value);
  final int value;
}

class _OtherEvent extends GameEvent {
  const _OtherEvent();
}

void main() {
  test('подписчик получает только события своего типа', () async {
    final bus = EventBus();
    final received = <int>[];

    final sub = bus.on<_TestEvent>().listen((event) => received.add(event.value));

    bus.fire(const _TestEvent(1));
    bus.fire(const _OtherEvent());
    bus.fire(const _TestEvent(2));

    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(received, [1, 2]);
  });
}
