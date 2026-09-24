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
              onTap: _busy
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
          if (_deleteBranch && _branchStatus?.merged == false)
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
                  Text(
                    'Force delete unmerged branch',
                    style: TextStyle(color: visual.foreground),
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
          label: 'Remove worktree',
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
    if (_deleteBranch && _forceBranch && _branchStatus?.merged == false) {
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
    if (status.dirty) {
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
    final run = await ref
        .read(gitActionsControllerProvider)
        .removeWorktreeWithBranch(
          widget.repo,
          widget.worktree.path,
          force: force,
          deleteBranch: _deleteBranch,
          forceBranch: _forceBranch,
        );
    if (!mounted) return;
    if (run.value?.error == null && run.status == ActionRunStatus.succeeded) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = false;
      _error =
          run.value?.error ??
          (run.status == ActionRunStatus.refreshFailed
              ? refreshFailureMessage
              : 'Removal could not complete.');
    });
  }
}
