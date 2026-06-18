import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Warning strip shown while HEAD is detached — previously the only hint was
/// the missing checkmark in the branch list, and commits made in this state
/// silently belong to no branch.
class DetachedHeadBanner extends ConsumerWidget {
  const DetachedHeadBanner({required this.repo, super.key});
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(repoStatusProvider(repo)).value;
    if (status == null || !status.isDetached) {
      return const SizedBox.shrink();
    }
    final palette = AppPalette.of(context);
    final sha = status.headSha?.short() ?? 'unknown';
    return Container(
      width: double.infinity,
      color: palette.accentWarn.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_outlined,
            size: 14,
            color: palette.accentWarn,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Detached HEAD at $sha — new commits will not belong to any '
              'branch. Check out or create a branch to keep them.',
              style: TextStyle(color: palette.fg1, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
