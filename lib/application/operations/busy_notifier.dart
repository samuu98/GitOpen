import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/legacy.dart';

/// One action the runner has in flight, and whether its indicator is on screen.
///
/// [running] and [visible] are deliberately independent: an action that
/// finishes before the show delay elapses never becomes visible, and one that
/// did become visible stays so for the minimum window after it stopped running.
class PendingAction extends Equatable {
  const PendingAction({
    required this.key,
    this.label,
    this.running = true,
    this.visible = false,
  });

  /// Identifies the action; also the double-submit guard's key.
  final String key;
  final String? label;
  final bool running;
  final bool visible;

  PendingAction copyWith({String? label, bool? running, bool? visible}) {
    return PendingAction(
      key: key,
      label: label ?? this.label,
      running: running ?? this.running,
      visible: visible ?? this.visible,
    );
  }

  @override
  List<Object?> get props => [key, label, running, visible];
}

/// The pending state of every action in flight, scoped by action key.
class BusyState extends Equatable {
  const BusyState([this.actions = const []]);
  final List<PendingAction> actions;

  /// Whether any action is still running (true from the first frame, so a
  /// guard can refuse a second submit before any indicator appears).
  bool get isBusy => actions.any((a) => a.running);

  /// Whether any action's indicator should be on screen.
  bool get isVisible => actions.any((a) => a.visible);

  bool isRunning(String key) =>
      actions.any((a) => a.key == key && a.running);

  bool isVisibleFor(String key) =>
      actions.any((a) => a.key == key && a.visible);

  /// Label of the most recently started running action.
  String? get label => _lastWhere((a) => a.running)?.label;

  /// Label of the indicator currently on screen.
  String? get visibleLabel => _lastWhere((a) => a.visible)?.label;

  PendingAction? _lastWhere(bool Function(PendingAction) test) {
    for (final action in actions.reversed) {
      if (test(action)) return action;
    }
    return null;
  }

  @override
  List<Object?> get props => [actions];
}

/// Tracks in-flight actions so the UI can block interaction and show scoped
/// pending indicators.
///
/// Keyed (not a plain counter) so a row or button can show its own pending
/// state and so the runner can refuse a duplicate submit of the same action.
/// The indicator only appears after [showDelay] — an action that completes
/// sooner shows nothing rather than flashing — and once it appears it stays
/// for at least [minVisible].
class BusyNotifier extends StateNotifier<BusyState> {
  BusyNotifier({required this.showDelay, required this.minVisible})
    : super(const BusyState());

  final Duration showDelay;
  final Duration minVisible;

  final Map<String, Timer> _showTimers = {};
  final Map<String, Timer> _holdTimers = {};

  void begin(String key, [String? label]) {
    _holdTimers.remove(key)?.cancel();
    final existing = _find(key);
    if (existing == null) {
      state = BusyState([
        ...state.actions,
        PendingAction(key: key, label: label),
      ]);
      _scheduleShow(key);
      return;
    }
    // Re-entering an action whose indicator is still in its minimum window:
    // keep it on screen instead of hiding and showing it again, and give the
    // new run its own minimum window.
    _replace(existing.copyWith(label: label, running: true));
    if (existing.visible) {
      _scheduleHold(key);
    } else {
      _scheduleShow(key);
    }
  }

  void end(String key) {
    _showTimers.remove(key)?.cancel();
    final existing = _find(key);
    if (existing == null) return;
    if (!existing.visible) {
      _remove(key);
      return;
    }
    // Shown: the hold timer removes it when the minimum window elapses.
    if (_holdTimers.containsKey(key)) {
      _replace(existing.copyWith(running: false));
      return;
    }
    _remove(key);
  }

  void _scheduleShow(String key) {
    _showTimers.remove(key)?.cancel();
    _showTimers[key] = Timer(showDelay, () {
      _showTimers.remove(key);
      final action = _find(key);
      if (action == null || !action.running) return;
      _replace(action.copyWith(visible: true));
      _scheduleHold(key);
    });
  }

  void _scheduleHold(String key) {
    _holdTimers.remove(key)?.cancel();
    _holdTimers[key] = Timer(minVisible, () {
      _holdTimers.remove(key);
      final held = _find(key);
      if (held != null && !held.running) _remove(key);
    });
  }

  PendingAction? _find(String key) {
    for (final action in state.actions) {
      if (action.key == key) return action;
    }
    return null;
  }

  void _replace(PendingAction action) {
    if (!mounted) return;
    state = BusyState([
      for (final a in state.actions) if (a.key == action.key) action else a,
    ]);
  }

  void _remove(String key) {
    _holdTimers.remove(key)?.cancel();
    if (!mounted) return;
    state = BusyState([
      for (final a in state.actions)
        if (a.key != key) a,
    ]);
  }

  @override
  void dispose() {
    for (final timer in [..._showTimers.values, ..._holdTimers.values]) {
      timer.cancel();
    }
    _showTimers.clear();
    _holdTimers.clear();
    super.dispose();
  }
}
