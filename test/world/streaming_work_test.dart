import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:crime_oren/world/streaming_work.dart';

void main() {
  test(
    'material preparation yields after four items even for immediate futures',
    () async {
      var frame = 0;
      final seen = <int>[];
      await FramePreparation(
        yieldToFrame: () async {
          frame++;
        },
        budget: const Duration(seconds: 10),
      ).run(List.generate(10, (i) => i), (_) async {
        seen.add(frame);
      });
      expect(seen, [0, 0, 0, 0, 1, 1, 1, 1, 2, 2]);
    },
  );
  test('unloaded chunks stop preparing after a frame boundary', () async {
    var current = true, count = 0;
    await FramePreparation(
      yieldToFrame: () async {
        current = false;
      },
      maxItems: 2,
    ).run([1, 2, 3, 4], (_) async {
      count++;
    }, isCurrent: () => current);
    expect(count, 2);
  });
  test('next chunk waits for preparation as well as import', () async {
    final frame = Completer<void>();
    final events = <String>[];
    final queue = StreamingWork<void>();
    final a = queue.schedule('a', () async {
      events.add('import a');
      await FramePreparation(yieldToFrame: () => frame.future, maxItems: 1).run(
        [1, 2],
        (i) async {
          events.add('material $i');
        },
      );
    });
    final b = queue.schedule('b', () async {
      events.add('import b');
    });
    await Future<void>.delayed(Duration.zero);
    expect(events, ['import a', 'material 1']);
    frame.complete();
    await a;
    await b;
    expect(events, ['import a', 'material 1', 'material 2', 'import b']);
  });

  test(
    'imports are serial, duplicate requests share a future and yield between jobs',
    () async {
      final first = Completer<int>(), yieldFrame = Completer<void>();
      final events = <String>[];
      final queue = StreamingWork<int>(
        yieldToFrame: () {
          events.add('yield');
          return yieldFrame.future;
        },
      );
      final a = queue.schedule('a', () {
        events.add('a');
        return first.future;
      });
      final duplicate = queue.schedule(
        'a',
        () async => throw StateError('duplicate import'),
      );
      final b = queue.schedule('b', () async {
        events.add('b');
        return 2;
      });
      expect(identical(a, duplicate), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(events, ['a']);
      first.complete(1);
      expect(await a, 1);
      await Future<void>.delayed(Duration.zero);
      expect(events, ['a', 'yield']);
      yieldFrame.complete();
      expect(await b, 2);
      await Future<void>.delayed(Duration.zero);
      expect(queue.pendingCount, 0);
    },
  );
  test('a failed import does not block subsequent work or retries', () async {
    final queue = StreamingWork<int>();
    final failure = queue.schedule(
      'a',
      () async => throw StateError('bad asset'),
    );
    final next = queue.schedule('b', () async => 2);
    await expectLater(failure, throwsStateError);
    expect(await next, 2);
    expect(await queue.schedule('a', () async => 3), 3);
  });
  test('obsolete queued work can be skipped before reading an asset', () async {
    final first = Completer<int>();
    final queue = StreamingWork<int?>();
    var wanted = true, loaded = false;
    final a = queue.schedule('a', () => first.future);
    final b = queue.schedule('b', () async {
      if (!wanted) return null;
      loaded = true;
      return 2;
    });
    wanted = false;
    first.complete(1);
    await a;
    expect(await b, isNull);
    expect(loaded, isFalse);
  });
  test('a grid boundary does not repeatedly reload while oscillating', () {
    final center = StreamingCenter(cellSize: 200);
    expect(center.update(199, 1), isTrue);
    for (final x in [201.0, 198.0, 210.0, 195.0]) {
      expect(center.update(x, 1), isFalse);
      expect(center.cell, (0, 0));
    }
    expect(center.update(221, 1), isTrue);
    expect(center.cell, (1, 0));
    expect(center.update(199, 1), isFalse);
    expect(center.update(179, 1), isTrue);
    expect(center.cell, (0, 0));
    expect(center.update(-700, 900), isTrue);
    expect(center.cell, (-4, 4));
  });
}
