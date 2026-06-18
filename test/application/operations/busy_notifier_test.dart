import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/operations/busy_notifier.dart';

void main() {
  test('nested begin/end tracks depth and clears label at zero', () {
    final n = BusyNotifier();
    expect(n.state.isBusy, isFalse);

    n.begin('Fetching');
    expect(n.state.depth, 1);
    expect(n.state.isBusy, isTrue);
    expect(n.state.label, 'Fetching');

    n.begin('Checking out x');
    expect(n.state.depth, 2);
    expect(n.state.label, 'Checking out x');

    n.end();
    expect(n.state.depth, 1);

    n.end();
    expect(n.state.depth, 0);
    expect(n.state.isBusy, isFalse);
    expect(n.state.label, isNull);
  });

  test('end below zero stays clamped at idle', () {
    final n = BusyNotifier()..end();
    expect(n.state.depth, 0);
    expect(n.state.label, isNull);
  });
}
