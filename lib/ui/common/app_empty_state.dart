import 'package:flutter/material.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.icon,
    required this.title,
    super.key,
    this.message,
    this.actionIcon,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final IconData? actionIcon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    final typography = AppTypography.of(context);
    // Scrolls instead of overflowing when a short panel cannot fit it.
    return Center(
      child: SingleChildScrollView(
        padding: spacing.panel,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: spacing.panelIconSize, color: palette.fg3),
            SizedBox(height: spacing.sm),
            Text(
              title,
              textAlign: TextAlign.center,
              style: typography.bodyStrong.copyWith(color: palette.fg1),
            ),
            if (message != null) ...[
              SizedBox(height: spacing.xxs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: typography.body.copyWith(color: palette.fg3),
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: spacing.md),
              AppButton.primary(
                label: actionLabel!,
                icon: actionIcon ?? Icons.refresh,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
