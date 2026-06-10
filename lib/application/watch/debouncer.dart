import 'dart:async';

/// Coalesces bursts of triggers: each [trigger] (re)starts [window]; [action]
/// fires once when the window elapses with no further triggers.
final class Debouncer {
  Debouncer(this.window, this.action);
  final Duration window;
  final void Function() action;
  Timer? _timer;

  void trigger() {
    _timer?.cancel();
    _timer = Timer(window, action);
  }

  void dispose() => _timer?.cancel();
}
