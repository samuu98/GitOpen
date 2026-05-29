import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/git/git_result.dart';
import '../../application/providers.dart';
import '../../application/repo_revision.dart';
import '../../domain/repositories/repo_location.dart';
import '../../domain/status/working_file_entry.dart';
import '../dialogs/checkout_changes_dialog.dart';
import '../theme/app_palette.dart';

/// Performs `git checkout <ref>` after handling any uncommitted local
/// changes. If the working tree is clean, checks out immediately. If
/// it is dirty, prompts the user to discard, stash, or keep the changes.
///
/// Returns true on a successful checkout.
Future<bool> safeCheckout({
  required BuildContext context,
  required WidgetRef ref,
  required RepoLocation repo,
  required String targetRef,
}) async {
  final read = ref.read(gitReadOperationsProvider);
  final status = await read.getStatus(repo);
  final hasChanges = status.entries.any((e) =>
      e.workingTreeState != WorkingFileState.unmodified ||
      e.indexState != WorkingFileState.unmodified);

  CheckoutAction? action;
  if (hasChanges) {
    if (!context.mounted) return false;
    action = await CheckoutChangesDialog.show(context, targetRef);
    if (action == null) return false;
  }

  final write = ref.read(gitWriteOperationsProvider);

  switch (action) {
    case CheckoutAction.discard:
      final paths = status.entries.map((e) => e.path).toList();
      if (paths.isNotEmpty) {
        await write.discardChanges(repo, paths);
      }
    case CheckoutAction.stash:
      final stashRes = await write.stashSave(
        repo,
        'Auto-stash before checkout to $targetRef',
        includeUntracked: true,
      );
      if (stashRes is GitFailure<void>) {
        if (context.mounted) {
          _showError(context, 'Stash failed: ${stashRes.message}');
        }
        return false;
      }
    case CheckoutAction.keep:
    case null:
      break;
  }

  final result = await write.checkout(repo, targetRef);
  if (result is GitFailure<void>) {
    if (context.mounted) {
      _showError(context, 'Checkout failed: ${result.message}');
    }
    return false;
  }
  refreshRepo(ref, repo);
  return true;
}

void _showError(BuildContext context, String message) {
  if (!context.mounted) return;
  final palette = AppPalette.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: palette.accentErr,
    ),
  );
}
