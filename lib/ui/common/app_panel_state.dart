import 'package:flutter/material.dart';
import 'package:gitopen/ui/common/skeleton.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// One loading rule for every panel: list panels (sidebar, graph) keep their
/// skeleton silhouette; detail panels (commit details, diff, file tree) get
/// a single compact centered indicator. Both read their sizes and colours
/// from [AppSpacing]/[AppPalette] so they always match.
class AppLoadingState extends StatelessWidget {
  const AppLoadingState.list({
    super.key,
    this.rows = 12,
    this.rowHeight = 12,
    this.gap = 12,
  }) : _detail = false;

  const AppLoadingState.detail({super.key})
    : _detail = true,
      rows = 12,
      rowHeight = 12,
      gap = 12;

  final bool _detail;
  final int rows;
  final double rowHeight;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (!_detail) {
      return SkeletonList(rows: rows, rowHeight: rowHeight, gap: gap);
    }
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    return Center(
      child: SizedBox(
        width: spacing.detailIndicatorSize,
        height: spacing.detailIndicatorSize,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(palette.fg2),
        ),
      ),
    );
  }
}

/// Shared panel error treatment: a short message, git's detail when one is
/// available, and a [AppButton] retry action. Mirrors `AppEmptyState`'s
/// padding, type scale and icon size tokens.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    required this.message,
    super.key,
    this.detail,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.icon = Icons.error_outline,
  });

  final String message;
  final String? detail;
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    final typography = AppTypography.of(context);
    return Center(
      child: Padding(
        padding: spacing.panel,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: spacing.panelIconSize, color: palette.accentErr),
            SizedBox(height: spacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: typography.bodyStrong.copyWith(color: palette.fg1),
            ),
            if (detail != null && detail!.isNotEmpty) ...[
              SizedBox(height: spacing.xxs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  detail!,
                  textAlign: TextAlign.center,
                  style: typography.body.copyWith(color: palette.fg3),
                ),
              ),
            ],
            if (onRetry != null) ...[
              SizedBox(height: spacing.md),
              AppButton.secondary(
                label: retryLabel,
                icon: Icons.refresh,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
