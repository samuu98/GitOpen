import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/diff/build_patch_for_hunks.dart';
import 'package:gitopen/application/diff/build_patch_for_lines.dart';
import 'package:gitopen/application/git/build_stash_worktree_patch.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/operations/action_feedback.dart';
import 'package:gitopen/ui/toolbar/toolbar_prompt.dart';
import 'package:gitopen/ui/working_copy/discard_changes.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

/// A checked line set for one hunk (used by the line-level stage/unstage/
/// discard operations).
typedef LineSelection = ({DiffHunk hunk, Set<int> lines});

/// The git actions behind a working-copy file row: stage/unstage at file,
/// hunk, and line granularity, plus stash and discard. Holds no widget state —
/// the row keeps its selection and clears it after a call. Dialog/progress
/// actions (stash, discard) take a [BuildContext]; the confirm/prompt dialogs
/// and the `GitActionsController` live behind them. Methods that show a
/// confirmation return `true` when the action proceeded so the caller knows
/// whether to clear its selection.
final class FileRowActions {
  FileRowActions(this._ref);
  final WidgetRef _ref;

  // --- File-level ---------------------------------------------------------

  Future<bool> toggleStage(
    RepoLocation repo,
    String path, {
    required bool isStaged,
  }) async {
    final write = _ref.read(gitWriteOperationsProvider);
    return _runWrite(
      repo,
      path,
      isStaged ? 'Unstage' : 'Stage',
      () => isStaged
          ? write.unstageFiles(repo, [path])
          : write.stageFiles(repo, [path]),
    );
  }

  Future<void> stash(
    BuildContext context,
    RepoLocation repo,
    WorkingFileEntry entry,
  ) async {
    final msg = await appPromptText(
      context,
      'Stash file',
      label: 'Message (optional)',
    );
    if (!context.mounted) return;
    await _ref
        .read(gitActionsControllerProvider)
        .stashSave(
          context,
          repo,
          msg?.trim() ?? '',
          includeUntracked:
              entry.workingTreeState == WorkingFileState.untracked,
          paths: [entry.path],
        );
    _invalidateDiffs(repo, entry.path);
  }

  Future<void> discardFile(
    BuildContext context,
    RepoLocation repo,
    WorkingFileEntry entry,
  ) async {
    final isUntracked = entry.workingTreeState == WorkingFileState.untracked;
    final confirmed = await ConfirmDialog.show(
      context,
      title: isUntracked ? 'Delete untracked file?' : 'Discard changes?',
      body: isUntracked
          ? 'The file "${entry.path}" is untracked and will be removed '
                'from disk. This cannot be undone.'
          : 'Local edits to "${entry.path}" will be lost and the file will '
                'be restored to its committed state.',
      confirmLabel: isUntracked ? 'Delete' : 'Discard',
      dangerous: true,
    );
    if (!confirmed || !context.mounted) return;
    await discardEntries(context, _ref, repo, [entry]);
  }

  // --- Stage (unstaged rows) ---------------------------------------------

  Future<bool> stageHunks(
    RepoLocation repo,
    String path,
    List<DiffHunk> hunks,
  ) async {
    final patch = buildPatchForHunks(path, hunks);
    return _runWrite(
      repo,
      path,
      'Stage',
      () => _ref.read(gitWriteOperationsProvider).stagePatch(repo, patch),
    );
  }

  Future<bool> stageLines(
    RepoLocation repo,
    String path,
    List<LineSelection> selections,
  ) async {
    final patches = _patches(path, selections);
    if (patches.isEmpty) return false;
    final write = _ref.read(gitWriteOperationsProvider);
    return _runWrite(repo, path, 'Stage', () async {
      for (final patch in patches) {
        final result = await write.stagePatch(repo, patch);
        if (result is GitFailure<void>) return result;
      }
      return const GitSuccess<void>(null);
    });
  }

  Future<bool> stashHunks(
    RepoLocation repo,
    String path,
    List<DiffHunk> hunks,
  ) => _stashPatches(repo, path, [buildPatchForHunks(path, hunks)]);

  Future<bool> stashLines(
    RepoLocation repo,
    String path,
    List<LineSelection> selections,
  ) => _stashPatches(
    repo,
    path,
    _patches(path, selections),
    worktreePatches: [
      for (final selection in selections)
        if (selection.lines.isNotEmpty)
          buildStashWorktreePatch(path, selection.hunk, selection.lines),
    ],
  );

  Future<bool> _stashPatches(
    RepoLocation repo,
    String path,
    List<String> patches, {
    List<String>? worktreePatches,
  }) async {
    if (patches.isEmpty) return false;
    final result = await _ref
        .read(gitActionsServiceProvider)
        .stashPatch(
          repo,
          patches,
          'Selected changes in $path',
          worktreePatches: worktreePatches,
        );
    if (result.outcome != ActionOutcome.success) {
      _ref
          .read(actionFeedbackProvider)
          .showActionFailure(
            result.message ?? 'Stash failed',
            label: 'Stash',
          );
      return false;
    }
    _invalidateDiffs(repo, path);
    return true;
  }

  // --- Unstage (staged rows) — reverse-apply the index-vs-HEAD patch via
  // `git apply --cached --reverse`; non-destructive, so no confirm. ---

  Future<bool> unstageHunks(
    RepoLocation repo,
    String path,
    List<DiffHunk> hunks,
  ) async {
    final patch = buildPatchForHunks(path, hunks);
    return _runWrite(
      repo,
      path,
      'Unstage',
      () => _ref.read(gitWriteOperationsProvider).unstagePatch(repo, patch),
    );
  }

  Future<bool> unstageLines(
    RepoLocation repo,
    String path,
    List<LineSelection> selections,
  ) async {
    final patches = _patches(path, selections);
    if (patches.isEmpty) return false;
    final write = _ref.read(gitWriteOperationsProvider);
    return _runWrite(repo, path, 'Unstage', () async {
      for (final patch in patches) {
        final result = await write.unstagePatch(repo, patch);
        if (result is GitFailure<void>) return result;
      }
      return const GitSuccess<void>(null);
    });
  }

  Future<bool> unstageHunk(
    RepoLocation repo,
    String path,
    DiffHunk hunk,
  ) async {
    final patch = buildPatchForHunks(path, [hunk]);
    return _runWrite(
      repo,
      path,
      'Unstage',
      () => _ref.read(gitWriteOperationsProvider).unstagePatch(repo, patch),
    );
  }

  // --- Discard (unstaged rows) — reverse-apply to the working tree via the
  // shared discard flow (confirm + progress). Returns whether it proceeded. ---

  Future<bool> discardHunk(
    BuildContext context,
    RepoLocation repo,
    String path,
    DiffHunk hunk,
  ) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Discard hunk?',
      body: 'Local edits in this hunk from "$path" will be lost.',
      confirmLabel: 'Discard hunk',
      dangerous: true,
    );
    if (!confirmed || !context.mounted) return false;
    final patch = buildPatchForHunks(path, [hunk]);
    return _runWrite(
      repo,
      path,
      'Discard',
      () => _ref.read(gitWriteOperationsProvider).discardPatch(repo, patch),
    );
  }

  Future<bool> discardSelectedHunks(
    BuildContext context,
    RepoLocation repo,
    String path,
    List<DiffHunk> hunks,
  ) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Discard selected hunks?',
      body: 'Local edits in the selected hunks from "$path" will be lost.',
      confirmLabel: 'Discard',
      dangerous: true,
    );
    if (!confirmed || !context.mounted) return false;
    final patch = buildPatchForHunks(path, hunks);
    return _runWrite(
      repo,
      path,
      'Discard',
      () => _ref.read(gitWriteOperationsProvider).discardPatch(repo, patch),
    );
  }

  Future<bool> discardSelectedLines(
    BuildContext context,
    RepoLocation repo,
    String path,
    List<LineSelection> selections,
  ) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Discard selected lines?',
      body: 'Local edits to the selected lines from "$path" will be lost.',
      confirmLabel: 'Discard',
      dangerous: true,
    );
    if (!confirmed || !context.mounted) return false;
    final patches = _patches(path, selections);
    if (patches.isEmpty) return false;
    final write = _ref.read(gitWriteOperationsProvider);
    return _runWrite(repo, path, 'Discard', () async {
      for (final patch in patches) {
        final result = await write.discardPatch(repo, patch);
        if (result is GitFailure<void>) return result;
      }
      return const GitSuccess<void>(null);
    });
  }

  // --- Helpers ------------------------------------------------------------

  Future<bool> _runWrite(
    RepoLocation repo,
    String path,
    String label,
    Future<GitResult<void>> Function() action,
  ) async {
    final run = await _ref
        .read(actionRunnerProvider)
        .runAndRefresh<GitResult<void>>(
          key: 'working-copy:$path',
          repo: repo,
          scopes: const {RefreshScope.status, RefreshScope.workingCopy},
          action: action,
          failed: (result) => result is GitFailure<void>,
          label: label,
        );
    if (run.value case final GitFailure<void> failure) {
      _ref
          .read(actionFeedbackProvider)
          .showActionFailure(
            '$label failed: ${failure.message}',
            label: label,
          );
    }
    return run.status == ActionRunStatus.succeeded;
  }

  List<String> _patches(String path, List<LineSelection> selections) {
    final patches = <String>[];
    for (final s in selections) {
      if (s.lines.isEmpty) continue;
      final patch = buildPatchForLines(path, s.hunk, s.lines);
      if (patch.isNotEmpty) patches.add(patch);
    }
    return patches;
  }

  void _invalidateDiffs(RepoLocation repo, String path) {
    _ref
      ..invalidate(repoStatusProvider(repo))
      ..invalidate(unstagedFileDiffProvider((repo, path)))
      ..invalidate(stagedFileDiffProvider((repo, path)));
  }
}
