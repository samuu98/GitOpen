import 'package:flutter_riverpod/legacy.dart';

/// Set of `Branch.fullName` values that are CURRENTLY HIDDEN.
/// We invert (track hidden, not visible) so that fresh repos default to
/// "everything visible" without needing to pre-populate.
class HiddenRefsNotifier extends StateNotifier<Set<String>> {
  HiddenRefsNotifier() : super(<String>{});

  void toggle(String fullName) {
    final next = Set<String>.from(state);
    if (!next.add(fullName)) next.remove(fullName);
    state = next;
  }

  void clear() {
    state = <String>{};
  }

  bool isHidden(String fullName) => state.contains(fullName);
}

final hiddenRefsProvider =
    StateNotifierProvider<HiddenRefsNotifier, Set<String>>((ref) {
  return HiddenRefsNotifier();
});
