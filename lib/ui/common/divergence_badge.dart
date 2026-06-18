import 'package:flutter/material.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Small `↑ahead ↓behind` badge for a branch's divergence from its upstream.
/// Renders an empty box when both are zero. ↑ = commits to push, ↓ = to pull.
class DivergenceBadge extends StatelessWidget {
  const DivergenceBadge({required this.ahead, required this.behind, super.key});
  final int ahead;
  final int behind;

  @override
  Widget build(BuildContext context) {
    if (ahead == 0 && behind == 0) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final parts = <String>[
      if (ahead > 0) '↑$ahead',
      if (behind > 0) '↓$behind',
    ];
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        parts.join(' '),
        style: TextStyle(
          color: palette.fg2,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
