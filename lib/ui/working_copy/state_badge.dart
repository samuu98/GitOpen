import 'package:flutter/material.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/common/app_icon_button.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class DiscardIconButton extends StatelessWidget {
  const DiscardIconButton({
    required this.isSelected,
    required this.onPressed,
    super.key,
  });
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: AppIconButton(
        icon: Icons.delete_outline,
        tooltip: 'Discard changes',
        danger: !isSelected,
        onPressed: onPressed,
      ),
    );
  }
}

class StateBadge extends StatelessWidget {
  const StateBadge({required this.state, super.key});
  final WorkingFileState state;
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final (label, color) = _info(state, p);
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  (String, Color) _info(WorkingFileState s, AppPalette p) {
    switch (s) {
      case WorkingFileState.added:
        return ('A', p.accentCurrent);
      case WorkingFileState.modified:
        return ('M', p.accentTag);
      case WorkingFileState.deleted:
        return ('D', p.accentErr);
      case WorkingFileState.renamed:
        return ('R', p.accentRemote);
      case WorkingFileState.untracked:
        return ('?', p.fg2);
      case WorkingFileState.conflicted:
        return ('U', p.accentWarn);
      case WorkingFileState.ignored:
        return ('I', p.fg3);
      case WorkingFileState.unmodified:
        return ('', Colors.transparent);
    }
  }
}
