import 'package:flutter/material.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Shown under a truncated file diff: explains the cap and offers the
/// uncapped single-file fetch.
class TruncatedDiffBanner extends StatelessWidget {
  const TruncatedDiffBanner({required this.onLoadFull, super.key});
  final VoidCallback onLoadFull;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: palette.bg3,
      child: Row(
        children: [
          Icon(Icons.unfold_more, size: 14, color: palette.fg2),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Large diff truncated for performance.',
              style: TextStyle(color: palette.fg2, fontSize: 12),
            ),
          ),
          AppButton.secondary(
            label: 'Load full diff',
            onPressed: onLoadFull,
            compact: true,
          ),
        ],
      ),
    );
  }
}
