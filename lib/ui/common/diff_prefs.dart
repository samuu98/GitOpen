import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Whether diff views highlight the changed region inside paired
/// removed/added lines (intraline "word diff"). Session-scoped.
final wordDiffEnabledProvider = StateProvider<bool>((_) => false);

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
