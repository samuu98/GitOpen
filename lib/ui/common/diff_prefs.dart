import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Whether diff views highlight the changed region inside paired
/// removed/added lines (intraline "word diff"). Session-scoped.
final wordDiffEnabledProvider = StateProvider<bool>((_) => false);

/// How diff hunks are laid out. Session-scoped.
enum DiffViewMode { unified, sideBySide }

final diffViewModeProvider =
    StateProvider<DiffViewMode>((_) => DiffViewMode.unified);

/// Whether the commit diff view passes `-w` to git. Deliberately not applied
/// to the working-copy preview because its hunks feed patch operations.
final ignoreWhitespaceProvider = StateProvider<bool>((_) => false);

/// Small toggle for [wordDiffEnabledProvider], shown in diff headers.
class WordDiffToggle extends ConsumerWidget {
  const WordDiffToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final enabled = ref.watch(wordDiffEnabledProvider);
    return Tooltip(
      message: enabled
          ? 'Word diff on — click to show plain lines'
          : 'Word diff off — click to highlight changed text within lines',
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        borderRadius: BorderRadius.circular(3),
        onTap: () =>
            ref.read(wordDiffEnabledProvider.notifier).state = !enabled,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            Icons.text_fields,
            size: 14,
            color: enabled ? palette.accentCurrent : palette.fg3,
          ),
        ),
      ),
    );
  }
}

/// Toggle for [diffViewModeProvider], shown in diff headers.
class SplitDiffToggle extends ConsumerWidget {
  const SplitDiffToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final mode = ref.watch(diffViewModeProvider);
    final split = mode == DiffViewMode.sideBySide;
    return Tooltip(
      message: split
          ? 'Side-by-side - click for unified'
          : 'Unified - click for side-by-side',
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        borderRadius: BorderRadius.circular(3),
        onTap: () => ref.read(diffViewModeProvider.notifier).state =
            split ? DiffViewMode.unified : DiffViewMode.sideBySide,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            Icons.vertical_split,
            size: 14,
            color: split ? palette.accentCurrent : palette.fg3,
          ),
        ),
      ),
    );
  }
}

/// Toggle for [ignoreWhitespaceProvider], shown in the commit diff header.
class IgnoreWhitespaceToggle extends ConsumerWidget {
  const IgnoreWhitespaceToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final enabled = ref.watch(ignoreWhitespaceProvider);
    return Tooltip(
      message: enabled
          ? 'Whitespace ignored (-w) - click to include'
          : 'Whitespace shown - click to ignore (-w)',
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        borderRadius: BorderRadius.circular(3),
        onTap: () =>
            ref.read(ignoreWhitespaceProvider.notifier).state = !enabled,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            Icons.space_bar,
            size: 14,
            color: enabled ? palette.accentCurrent : palette.fg3,
          ),
        ),
      ),
    );
  }
}
