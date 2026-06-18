import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Whether a blocking git operation is in flight, and its label.
class BusyState extends Equatable {
  const BusyState({this.depth = 0, this.label});
  final int depth;
  final String? label;

  bool get isBusy => depth > 0;

  @override
  List<Object?> get props => [depth, label];
}

/// Counts in-flight controller actions so the UI can block interaction while
/// a git operation runs. A counter (not a bool) so nested operations keep the
/// overlay up until all finish; `label` is the most recently started op.
class BusyNotifier extends StateNotifier<BusyState> {
  BusyNotifier() : super(const BusyState());

  void begin([String? label]) =>
      state = BusyState(depth: state.depth + 1, label: label);

  void end() {
    final depth = state.depth - 1;
    state = depth <= 0
        ? const BusyState()
        : BusyState(depth: depth, label: state.label);
  }
}
