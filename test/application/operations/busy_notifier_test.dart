import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/operations/busy_notifier.dart';

const _delay = Duration(milliseconds: 150);
const _minimum = Duration(milliseconds: 400);

BusyNotifier _notifier() =>
    BusyNotifier(showDelay: _delay, minVisible: _minimum);

void main() {
  test('nested begin/end tracks each key and clears label at idle', () {
    final n = _notifier();
    expect(n.state.isBusy, isFalse);

    n.begin('fetch', 'Fetching');
    expect(n.state.isBusy, isTrue);
    expect(n.state.isRunning('fetch'), isTrue);
    expect(n.state.label, 'Fetching');

    n.begin('checkout', 'Checking out x');
    expect(n.state.label, 'Checking out x');

    n.end('checkout');
    expect(n.state.isRunning('checkout'), isFalse);
    expect(n.state.isBusy, isTrue);
    expect(n.state.label, 'Fetching');

    n.end('fetch');
    expect(n.state.isBusy, isFalse);
    expect(n.state.label, isNull);
    n.dispose();
  });

  test('ending an unknown key is a no-op', () {
    final n = _notifier()..end('never-started');
    expect(n.state.isBusy, isFalse);
    expect(n.state.actions, isEmpty);
    n.dispose();
  });

  test('an action shorter than the delay never becomes visible', () {
    fakeAsync((async) {
      final n = _notifier()..begin('fetch', 'Fetching');
      async.elapse(const Duration(milliseconds: 100));
      expect(n.state.isVisible, isFalse);
      n.end('fetch');
      async.elapse(const Duration(seconds: 1));
      expect(n.state.isVisible, isFalse);
      expect(n.state.actions, isEmpty);
      n.dispose();
    });
  });

  test('a shown indicator is held for the minimum window', () {
    fakeAsync((async) {
      final n = _notifier()..begin('fetch', 'Fetching');
      async.elapse(_delay);
      expect(n.state.isVisible, isTrue);
      expect(n.state.visibleLabel, 'Fetching');

      n.end('fetch');
      expect(n.state.isBusy, isFalse);
      expect(n.state.isVisible, isTrue, reason: 'held for the minimum');

      async.elapse(_minimum - const Duration(milliseconds: 1));
      expect(n.state.isVisible, isTrue);
      async.elapse(const Duration(milliseconds: 2));
      expect(n.state.isVisible, isFalse);
      expect(n.state.actions, isEmpty);
      n.dispose();
    });
  });

  test('re-entering a key inside its hold keeps the indicator up', () {
    fakeAsync((async) {
      final n = _notifier()..begin('fetch', 'Fetching');
      async.elapse(_delay);
      n
        ..end('fetch')
        ..begin('fetch', 'Fetching again');
      async.elapse(_minimum + const Duration(milliseconds: 10));
      expect(n.state.isVisible, isTrue);
      expect(n.state.visibleLabel, 'Fetching again');
      n
        ..end('fetch')
        ..dispose();
    });
  });
}
