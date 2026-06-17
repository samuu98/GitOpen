import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/diff/build_patch_for_hunks.dart';
import 'package:gitopen/application/diff/build_patch_for_lines.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
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

  Future<void> toggleStage(
    RepoLocation repo,
    String path, {
    required bool isStaged,
  }) async {
    final write = _ref.read(gitWriteOperationsProvider);
    if (isStaged) {
      await write.unstageFiles(repo, [path]);
    } else {
      await write.stageFiles(repo, [path]);
    }
    _ref.invalidate(workingCopyStatusProvider(repo));
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
      title: isUntracked ? 'Delete untracked file' : 'Discard changes',
      body: isUntracked
          ? 'Delete "${entry.path}"? The file is untracked and will be '
                'removed from disk. This cannot be undone.'
          : 'Discard all changes to "${entry.path}"? Local edits will be '
                'lost and the file will be restored to its committed state.',
      confirmLabel: isUntracked ? 'Delete' : 'Discard',
      dangerous: true,
    );
    if (!confirmed) return;
    await discardEntries(_ref, repo, [entry]);
  }

  // --- Stage (unstaged rows) ---------------------------------------------

  Future<void> stageHunks(
    RepoLocation repo,
    String path,
    List<DiffHunk> hunks,
  ) async {
    final patch = buildPatchForHunks(path, hunks);
    await _ref.read(gitWriteOperationsProvider).stagePatch(repo, patch);
    _ref
      ..invalidate(workingCopyStatusProvider(repo))
      ..invalidate(unstagedFileDiffProvider((repo, path)));
  }

  Future<void> stageLines(
    RepoLocation repo,
    String path,
    List<LineSelection> selections,
  ) async {
    final patches = _patches(path, selections);
    if (patches.isEmpty) return;
    final write = _ref.read(gitWriteOperationsProvider);
    for (final patch in patches) {
      await write.stagePatch(repo, patch);
    }
    _ref
      ..invalidate(workingCopyStatusProvider(repo))
      ..invalidate(unstagedFileDiffProvider((repo, path)));
  }

  // --- Unstage (staged rows) — reverse-apply the index-vs-HEAD patch via
  // `git apply --cached --reverse`; non-destructive, so no confirm. ---

  Future<void> unstageHunks(
    RepoLocation repo,
    String path,
    List<DiffHunk> hunks,
  ) async {
    final patch = buildPatchForHunks(path, hunks);
    await _ref.read(gitWriteOperationsProvider).unstagePatch(repo, patch);
    _invalidateDiffs(repo, path);
  }

  Future<void> unstageLines(
    RepoLocation repo,
    String path,
    List<LineSelection> selections,
  ) async {
    final patches = _patches(path, selections);
    if (patches.isEmpty) return;
    final write = _ref.read(gitWriteOperationsProvider);
    for (final patch in patches) {
      await write.unstagePatch(repo, patch);
    }
    _invalidateDiffs(repo, path);
  }

  Future<void> unstageHunk(
    RepoLocation repo,
    String path,
    DiffHunk hunk,
  ) async {
    final patch = buildPatchForHunks(path, [hunk]);
    await _ref.read(gitWriteOperationsProvider).unstagePatch(repo, patch);
    _invalidateDiffs(repo, path);
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
      title: 'Discard hunk',
      body:
          'Discard this hunk from "$path"? Local edits in the hunk will '
          'be lost.',
      confirmLabel: 'Discard hunk',
      dangerous: true,
    );
    if (!confirmed || !context.mounted) return false;
    final patch = buildPatchForHunks(path, [hunk]);
    await _ref
        .read(gitActionsControllerProvider)
        .discardHunk(context, repo, patch);
    _ref
      ..invalidate(workingCopyStatusProvider(repo))
      ..invalidate(unstagedFileDiffProvider((repo, path)));
    return true;
  }

  Future<bool> discardSelectedHunks(
    BuildContext context,
    RepoLocation repo,
    String path,
    List<DiffHunk> hunks,
  ) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Discard selected hunks',
      body:
          'Discard the selected hunks from "$path"? Local edits in them '
          'will be lost.',
      confirmLabel: 'Discard',
      dangerous: true,
    );
    if (!confirmed || !context.mounted) return false;
    final patch = buildPatchForHunks(path, hunks);
    await _ref
        .read(gitActionsControllerProvider)
        .discardHunk(context, repo, patch);
    _invalidateDiffs(repo, path);
    return true;
  }

  Future<bool> discardSelectedLines(
    BuildContext context,
    RepoLocation repo,
    String path,
    List<LineSelection> selections,
  ) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Discard selected lines',
      body:
          'Discard the selected lines from "$path"? Local edits to them '
          'will be lost.',
      confirmLabel: 'Discard',
      dangerous: true,
    );
    if (!confirmed || !context.mounted) return false;
    final patches = _patches(path, selections);
    if (patches.isEmpty) return false;
    final controller = _ref.read(gitActionsControllerProvider);
    for (final patch in patches) {
      await controller.discardHunk(context, repo, patch);
      if (!context.mounted) return true;
    }
    _invalidateDiffs(repo, path);
    return true;
  }

  // --- Helpers ------------------------------------------------------------

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
      ..invalidate(workingCopyStatusProvider(repo))
      ..invalidate(unstagedFileDiffProvider((repo, path)))
      ..invalidate(stagedFileDiffProvider((repo, path)));
  }
}
