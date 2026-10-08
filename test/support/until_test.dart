import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'until.dart';

/// A [ValueNotifier] that says whether anyone still listens.
final class _Value extends ValueNotifier<int> {
  _Value(super.value);

  bool get listened => hasListeners;
}

void main() {
  test('holds already: completes at once, without a notification', () async {
    final value = _Value(1);
    addTearDown(value.dispose);

    await untilNotified(value, () => value.value == 1, what: 'one');
  });

  test('completes on the notification that makes it hold, and stops '
      'listening', () async {
    final value = _Value(0);
    addTearDown(value.dispose);
    var done = false;
    final waiting = untilNotified(
      value,
      () => value.value == 2,
      what: 'two',
    ).then((_) => done = true);

    value.value = 1;
    await pumpEventQueue();
    expect(done, isFalse);
    value.value = 2;
    await waiting;

    expect(done, isTrue);
    expect(value.listened, isFalse);
  });

  test('fails with what it waited for once the timeout passes', () async {
    final value = _Value(0);
    addTearDown(value.dispose);

    await expectLater(
      untilNotified(
        value,
        () => value.value == 1,
        what: 'one',
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(
        isA<TestFailure>().having(
          (f) => f.message,
          'message',
          contains('Timed out after 0:00:00.020000: one'),
        ),
      ),
    );
    expect(value.listened, isFalse);
  });
}
