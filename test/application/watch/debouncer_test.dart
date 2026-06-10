import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/watch/debouncer.dart';

void main() {
  test('fires once after the window, coalescing bursts', () {
    fakeAsync((async) {
      var fired = 0;
      final d = Debouncer(const Duration(milliseconds: 400), () => fired++);
      d.trigger();
      async.elapse(const Duration(milliseconds: 200));
      d.trigger(); // restarts the window
      async.elapse(const Duration(milliseconds: 399));
      expect(fired, 0);
      async.elapse(const Duration(milliseconds: 1));
      expect(fired, 1);
      d.trigger();
      async.elapse(const Duration(milliseconds: 400));
      expect(fired, 2);
      d.dispose();
    });
  });

  test('dispose cancels a pending fire', () {
    fakeAsync((async) {
      var fired = 0;
      Debouncer(const Duration(milliseconds: 400), () => fired++)
        ..trigger()
        ..dispose();
      async.elapse(const Duration(seconds: 1));
      expect(fired, 0);
    });
  });
}
