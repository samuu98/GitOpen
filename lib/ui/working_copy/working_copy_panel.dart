import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/common/horizontal_splitter.dart';
import 'package:gitopen/ui/common/skeleton.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/commit_compose.dart';
import 'package:gitopen/ui/working_copy/diff_preview_pane.dart';
import 'package:gitopen/ui/working_copy/file_list.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

class WorkingCopyPanel extends ConsumerWidget {
  const WorkingCopyPanel({required this.repo, super.key});
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(workingCopyStatusProvider(repo));
    final palette = AppPalette.of(context);
    return ColoredBox(
      color: palette.bg1,
      child: async.when(
        // Keep the change list visible during background reloads.
        skipLoadingOnReload: true,
        loading: () => const SkeletonList(rows: 8),
        error: (e, _) => Center(
          child: Text('Error: $e', style: TextStyle(color: palette.accentErr)),
        ),
        data: (entries) {
          final unstaged = entries.where((e) =>
              e.workingTreeState != WorkingFileState.unmodified).toList();
          final staged = entries.where((e) =>
              e.indexState != WorkingFileState.unmodified).toList();
          // Left pane (file list + commit box) is resizable; drag the handle
          // to widen it so long file paths fit. Right pane shows the diff.
          return HorizontalSplitter(
            left: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: FileList(
                  repo: repo, unstaged: unstaged, staged: staged,
                )),
                Divider(height: 1, color: palette.border),
                CommitCompose(repo: repo, hasStaged: staged.isNotEmpty),
              ],
            ),
            right: DiffPreviewPane(repo: repo),
          );
        },
      ),
    );
  }
}
