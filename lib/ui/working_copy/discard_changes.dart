import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

/// Discards working-tree changes for the supplied entries.
///
/// Untracked files cannot be checkout-restored, so they go through
/// `git clean`; tracked files use `git checkout -- <paths>`. Returns true
/// when the operation completed without errors.
Future<bool> discardEntries(
  BuildContext context,
  WidgetRef ref,
  RepoLocation repo,
  List<WorkingFileEntry> entries,
) async {
  final untracked = <String>[];
  final tracked = <String>[];
  for (final e in entries) {
    if (e.workingTreeState == WorkingFileState.untracked) {
      untracked.add(e.path);
    } else {
      tracked.add(e.path);
    }
  }
  final write = ref.read(gitWriteOperationsProvider);
  for (final (paths, run) in [
    (tracked, () => write.discardChanges(repo, tracked)),
    (untracked, () => write.cleanUntracked(repo, untracked)),
  ]) {
    if (paths.isEmpty) continue;
    final result = await run();
    if (result is GitFailure<void>) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Discard failed: ${result.message}'),
            backgroundColor: AppPalette.of(context).accentErr,
          ),
        );
      }
      ref.invalidate(workingCopyStatusProvider(repo));
      return false;
    }
  }
  ref.invalidate(workingCopyStatusProvider(repo));
  return true;
}

Future<void> confirmAndDiscardAll(
  BuildContext context,
  WidgetRef ref,
  RepoLocation repo,
  List<WorkingFileEntry> entries,
) async {
  final untrackedCount = entries
      .where((e) => e.workingTreeState == WorkingFileState.untracked)
      .length;
  final trackedCount = entries.length - untrackedCount;
  final parts = <String>[];
  if (trackedCount > 0) {
    parts.add(
      'discard local changes to $trackedCount tracked file'
      '${trackedCount == 1 ? '' : 's'}',
    );
  }
  if (untrackedCount > 0) {
    parts.add(
      'delete $untrackedCount untracked file'
      '${untrackedCount == 1 ? '' : 's'}',
    );
  }
  final confirmed = await ConfirmDialog.show(
    context,
    title: 'Discard all unstaged changes',
    body: 'This will ${parts.join(' and ')}. This cannot be undone.',
    confirmLabel: 'Discard all',
    dangerous: true,
  );
  if (!confirmed || !context.mounted) return;
  await discardEntries(context, ref, repo, entries);
}
