import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/dialogs/checkout_changes_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';

/// `origin/feat/x` → `feat/x`. Git remote names cannot contain `/`, so
/// stripping the first path segment is always exactly the remote prefix.
String localBranchNameFor(String remoteBranchName) =>
    remoteBranchName.split('/').skip(1).join('/');

/// Checks out [name] — a local branch, tag, or remote branch — after handling
/// any uncommitted local changes. Remote branches ([isRemote] true) check out
/// as a local tracking branch: an existing local branch with the same short
/// name is reused, otherwise `git checkout --track` creates it.
///
/// Returns true on a successful checkout.
Future<bool> checkoutRef({
  required BuildContext context,
  required WidgetRef ref,
  required RepoLocation repo,
  required String name,
  bool isRemote = false,
}) async {
  var targetRef = name;
  var trackRemote = false;
  if (isRemote) {
    final localName = localBranchNameFor(name);
    final branches =
        await ref.read(gitReadOperationsProvider).getBranches(repo);
    final localExists = branches.any((b) => !b.isRemote && b.name == localName);
    if (localExists) {
      targetRef = localName;
    } else {
      trackRemote = true;
    }
  }
  if (!context.mounted) return false;
  return safeCheckout(
    context: context,
    ref: ref,
    repo: repo,
    targetRef: targetRef,
    trackRemote: trackRemote,
  );
}

/// Performs the checkout after handling any uncommitted local changes. If the
/// working tree is clean, checks out immediately; if dirty, prompts the user
/// to discard, stash, or keep the changes. The checkout itself goes through
/// [GitActionsController] so failures surface a snackbar and invalidation is
/// consistent with every other action. With [trackRemote], [targetRef] is a
/// remote ref checked out via `git checkout --track`.
///
/// Returns true on a successful checkout.
Future<bool> safeCheckout({
  required BuildContext context,
  required WidgetRef ref,
  required RepoLocation repo,
  required String targetRef,
  bool trackRemote = false,
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

  final controller = ref.read(gitActionsControllerProvider);

  switch (action) {
    case CheckoutAction.discard:
      final paths = status.entries.map((e) => e.path).toList();
      if (paths.isNotEmpty) {
        await ref.read(gitWriteOperationsProvider).discardChanges(repo, paths);
      }
    case CheckoutAction.stash:
      if (!context.mounted) return false;
      final stashRes = await controller.stashSave(
        repo,
        'Auto-stash before checkout to $targetRef',
        includeUntracked: true,
      );
      if (stashRes.outcome != ActionOutcome.success) return false;
    case CheckoutAction.keep:
    case null:
      break;
  }

  if (!context.mounted) return false;
  final result = trackRemote
      ? await controller.checkoutTrack(repo, targetRef)
      : await controller.checkout(repo, targetRef);
  return result.outcome == ActionOutcome.success;
}
