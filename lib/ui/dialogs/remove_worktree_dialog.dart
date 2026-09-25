import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/branch_deletion_flow.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/refs/worktree.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class RemoveWorktreeDialog extends ConsumerStatefulWidget {
  const RemoveWorktreeDialog({
    required this.repo,
    required this.worktree,
    super.key,
  });

  final RepoLocation repo;
  final Worktree worktree;

  static Future<void> show(
    BuildContext context, {
    required RepoLocation repo,
    required Worktree worktree,
  }) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => RemoveWorktreeDialog(repo: repo, worktree: worktree),
  );

  @override
  ConsumerState<RemoveWorktreeDialog> createState() => _RemoveWorktreeState();
}

class _RemoveWorktreeState extends ConsumerState<RemoveWorktreeDialog> {
  WorktreeDeleteStatus? _status;
  bool _loading = true;
  bool _busy = false;
  bool _deleteBranch = false;
  bool _forceBranch = false;
  BranchDeleteStatus? _branchStatus;
  String? _error;

  /// Set when the worktree went but git refused its branch: what is left to do
  /// is the force delete of that branch alone.
  String? _refusedBranch;

  /// Set when the last run ended on a branch only `branch -D` deletes.
  bool _needsForce = false;

  bool get _branchUnmerged => _branchStatus?.merged == false || _needsForce;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final status = await ref
          .read(branchDeletionFlowProvider)
          .inspectWorktree(widget.repo, widget.worktree.path);
      BranchDeleteStatus? branchStatus;
      if (status?.branch case final branch?) {
        branchStatus = await ref
            .read(branchDeletionFlowProvider)
            .inspect(widget.repo, branch);
      }
      if (mounted) {
        setState(() {
          _status = status;
          _branchStatus = branchStatus;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final status = _status;
    return AppDialog(
      title: 'Remove worktree?',
      subtitle: 'Review the worktree before removing it',
      busy: _loading || _busy,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Path: ${widget.worktree.path}',
            style: TextStyle(color: palette.fg0),
          ),
          const SizedBox(height: 6),
          Text(
            'Branch: ${widget.worktree.branch ?? '(detached)'}',
            style: TextStyle(color: palette.fg1),
          ),
          if (status?.dirty == true) ...[
            const SizedBox(height: 10),
            Text(
              'Uncommitted or untracked changes will be lost if you '
              'force remove this worktree.',
              style: TextStyle(color: palette.accentErr),
            ),
          ],
          if (status?.locked == true || status?.isMain == true) ...[
            const SizedBox(height: 10),
            Text(
              status!.isMain
                  ? 'The main worktree cannot be removed.'
                  : 'This worktree is locked and cannot be removed.',
              style: TextStyle(color: palette.accentErr),
            ),
          ],
          if (widget.worktree.branch != null)
            AppInteractiveSurface(
              onTap: _busy || _refusedBranch != null
                  ? null
                  : () => setState(
                      () => _deleteBranch = !_deleteBranch,
                    ),
              selected: _deleteBranch,
              semanticLabel: 'Also delete the branch',
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: (context, visual) => Row(
                children: [
                  Icon(
                    _deleteBranch
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 17,
                    color: visual.foreground,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Also delete the branch',
                    style: TextStyle(color: visual.foreground),
                  ),
                ],
              ),
            ),
          if (_deleteBranch && _branchUnmerged)
            AppInteractiveSurface(
              onTap: _busy
                  ? null
                  : () => setState(
                      () => _forceBranch = !_forceBranch,
                    ),
              selected: _forceBranch,
              semanticLabel: 'Force delete unmerged branch',
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: (context, visual) => Row(
                children: [
                  Icon(
                    _forceBranch
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    size: 17,
                    color: visual.foreground,
                  ),
                  const SizedBox(width: 8),
                  // Expanded, not a bare Text: the label runs to the dialog's
                  // edge at this width.
                  Expanded(
                    child: Text(
                      'Force delete unmerged branch',
                      style: TextStyle(color: visual.foreground),
                    ),
                  ),
                ],
              ),
            ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: palette.accentErr)),
        ],
      ),
      actions: [
        AppButton.secondary(
          label: 'Cancel',
          onPressed: _busy ? null : () => Navigator.pop(context),
          autofocus: true,
        ),
        AppButton.danger(
          label: _refusedBranch == null ? 'Remove worktree' : 'Delete branch',
          onPressed:
              _busy ||
                  _loading ||
                  status == null ||
                  status.isMain ||
                  status.locked
              ? null
              : _remove,
        ),
      ],
    );
  }

  Future<void> _remove() async {
    final status = _status!;
    if (_deleteBranch && _forceBranch && _branchUnmerged) {
      final confirmed = await ConfirmDialog.show(
        context,
        title: 'Force delete branch?',
        body: 'Unmerged commits on "${status.branch}" will be lost.',
        confirmLabel: 'Force delete',
        dangerous: true,
      );
      if (!confirmed || !mounted) return;
    }
    var force = false;
    if (status.dirty && _refusedBranch == null) {
      force = await ConfirmDialog.show(
        context,
        title: 'Force remove dirty worktree?',
        body:
            'Uncommitted changes and untracked files in '
            '"${status.path}" will be lost.',
        confirmLabel: 'Force remove',
        dangerous: true,
      );
      if (!force || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final controller = ref.read(gitActionsControllerProvider);
    final ActionRun<BranchDeleteResult> run;
    if (_refusedBranch case final branch?) {
      // The worktree is already gone; the refused branch is all that is left.
      final batch = await controller.deleteBranches(context, widget.repo, [
        BranchDeleteRequest(branch, forceBranch: _forceBranch),
      ]);
      run = ActionRun(batch.status, value: batch.value?.firstOrNull);
    } else {
      run = await controller.removeWorktreeWithBranch(
        widget.repo,
        widget.worktree.path,
        force: force,
        deleteBranch: _deleteBranch,
        forceBranch: _forceBranch,
      );
    }
    if (!mounted) return;
    final result = run.value;
    // A refresh failure is the runner's toast: git did the work, so the dialog
    // closes exactly as it does on success.
    if (result?.error == null &&
        (run.status == ActionRunStatus.succeeded ||
            run.status == ActionRunStatus.refreshFailed)) {
      Navigator.pop(context);
      return;
    }
    final needsForce = result?.needsForce ?? false;
    setState(() {
      _busy = false;
      _needsForce = needsForce;
      // Only a refusal after the removal leaves the branch as all there is to
      // do; one before it keeps this a worktree removal.
      if (result != null && result.worktreeRemoved) {
        _refusedBranch = result.name;
      }
      _error = _refusedBranch != null && needsForce
          ? 'The worktree was removed, but branch "$_refusedBranch" is not '
                'fully merged and was kept. Enable force delete.'
          : result?.error ?? 'Removal could not complete.';
    });
  }
}
