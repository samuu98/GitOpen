import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gitopen/ui/common/app_icon_button.dart';

/// Whether diff views highlight the changed region inside paired
/// removed/added lines (intraline "word diff"). Session-scoped.
final wordDiffEnabledProvider = StateProvider<bool>((_) => false);

/// How diff hunks are laid out. Session-scoped.
enum DiffViewMode { unified, sideBySide }

final diffViewModeProvider = StateProvider<DiffViewMode>(
  (_) => DiffViewMode.unified,
);

/// Whether the commit diff view passes `-w` to git. Deliberately not applied
/// to the working-copy preview because its hunks feed patch operations.
final ignoreWhitespaceProvider = StateProvider<bool>((_) => false);

/// Small toggle for [wordDiffEnabledProvider], shown in diff headers.
class WordDiffToggle extends ConsumerWidget {
  const WordDiffToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(wordDiffEnabledProvider);
    return AppIconButton(
      icon: Icons.text_fields,
      tooltip: enabled
          ? 'Word diff on — click to show plain lines'
          : 'Word diff off — click to highlight changed text within lines',
      selected: enabled,
      onPressed: () =>
          ref.read(wordDiffEnabledProvider.notifier).state = !enabled,
    );
  }
}

/// Toggle for [diffViewModeProvider], shown in diff headers.
class SplitDiffToggle extends ConsumerWidget {
  const SplitDiffToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(diffViewModeProvider);
    final split = mode == DiffViewMode.sideBySide;
    return AppIconButton(
      icon: Icons.vertical_split,
      tooltip: split
          ? 'Side-by-side - click for unified'
          : 'Unified - click for side-by-side',
      selected: split,
      onPressed: () => ref.read(diffViewModeProvider.notifier).state = split
          ? DiffViewMode.unified
          : DiffViewMode.sideBySide,
    );
  }
}

/// Toggle for [ignoreWhitespaceProvider], shown in the commit diff header.
class IgnoreWhitespaceToggle extends ConsumerWidget {
  const IgnoreWhitespaceToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(ignoreWhitespaceProvider);
    return AppIconButton(
      icon: Icons.space_bar,
      tooltip: enabled
          ? 'Whitespace ignored (-w) - click to include'
          : 'Whitespace shown - click to ignore (-w)',
      selected: enabled,
      onPressed: () =>
          ref.read(ignoreWhitespaceProvider.notifier).state = !enabled,
    );
  }
}
