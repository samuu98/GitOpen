import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_icon_button.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Creates a linked worktree: a destination folder plus either a new branch
/// (created there) or an existing ref to check out.
class AddWorktreeDialog extends ConsumerStatefulWidget {
  const AddWorktreeDialog({required this.repo, super.key});
  final RepoLocation repo;

  /// Returns true when a worktree was created.
  static Future<bool> show(BuildContext context, RepoLocation repo) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => AddWorktreeDialog(repo: repo),
    );
    return created ?? false;
  }

  @override
  ConsumerState<AddWorktreeDialog> createState() => _State();
}

class _State extends ConsumerState<AddWorktreeDialog> {
  final _pathCtl = TextEditingController();
  final _branchCtl = TextEditingController();
  final _refCtl = TextEditingController();
  bool _busy = false;
  bool _created = false;
  String? _error;

  @override
  void dispose() {
    _pathCtl.dispose();
    _branchCtl.dispose();
    _refCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PopScope(
      canPop: !_busy,
      child: AppDialog(
        title: 'Add worktree',
        subtitle: 'Check out a second branch in its own folder',
        busy: _busy,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathCtl,
                    autofocus: true,
                    style: TextStyle(color: palette.fg0, fontSize: 13),
                    decoration: appInputDecoration(
                      context,
                      label: 'Destination folder',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                AppIconButton(
                  icon: Icons.folder_open,
                  tooltip: 'Browse…',
                  onPressed: _busy ? null : _pickDest,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _branchCtl,
              style: TextStyle(color: palette.fg0, fontSize: 13),
              decoration: appInputDecoration(
                context,
                label: 'New branch (created in the worktree)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _refCtl,
              style: TextStyle(color: palette.fg0, fontSize: 13),
              decoration: appInputDecoration(
                context,
                label: 'Or existing ref to check out (used when no new branch)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: palette.accentErr, fontSize: 11.5),
              ),
            ],
          ],
        ),
        actions: [
          AppButton.secondary(
            label: 'Cancel',
            onPressed: _busy ? null : () => Navigator.pop(context, false),
          ),
          AppButton.primary(
            label: _error == null ? 'Create' : 'Retry',
            onPressed: _busy ? null : _create,
          ),
        ],
      ),
    );
  }

  Future<void> _pickDest() async {
    final dir = await ref
        .read(folderPickerProvider)
        .pickFolder('Worktree folder');
    if (dir != null && mounted) _pathCtl.text = dir;
  }

  Future<void> _create() async {
    if (_busy) return;
    final path = _pathCtl.text.trim();
    if (path.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final newBranch = _branchCtl.text.trim();
    final existingRef = _refCtl.text.trim();
    if (_created) {
      try {
        final retry = await ref
            .read(actionRunnerProvider)
            .runAndRefresh<void>(
              key: 'add-worktree-refresh:$path',
              repo: widget.repo,
              scopes: const {RefreshScope.sidebar},
              action: () async {},
            );
        if (mounted && retry.status == ActionRunStatus.succeeded) {
          Navigator.pop(context, true);
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }
    final run = await ref
        .read(actionRunnerProvider)
        .runAndRefresh<GitResult<void>>(
          key: 'add-worktree:$path',
          repo: widget.repo,
          scopes: const {RefreshScope.sidebar},
          label: 'Adding worktree…',
          action: () => ref
              .read(gitWriteOperationsProvider)
              .addWorktree(
                widget.repo,
                path,
                newBranch: newBranch.isEmpty ? null : newBranch,
                ref: existingRef.isEmpty ? null : existingRef,
              ),
          failed: (result) => result is GitFailure<void>,
        );
    if (!mounted) return;
    switch (run.status) {
      case ActionRunStatus.succeeded:
        Navigator.pop(context, true);
      case ActionRunStatus.refreshFailed:
        _created = true;
        setState(() {
          _busy = false;
          _error = refreshFailureMessage;
        });
      case ActionRunStatus.failed:
        final result = run.value;
        setState(() {
          _busy = false;
          _error = result is GitFailure<void>
              ? result.message
              : 'Could not add worktree';
        });
      case ActionRunStatus.skipped || ActionRunStatus.stale:
        setState(() => _busy = false);
    }
  }
}
