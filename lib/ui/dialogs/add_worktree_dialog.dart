import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
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
    return AppDialog(
      title: 'Add worktree',
      subtitle: 'Check out a second branch in its own folder',
      busy: _busy,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _pathCtl,
                autofocus: true,
                style: TextStyle(color: palette.fg0, fontSize: 13),
                decoration:
                    appInputDecoration(context, label: 'Destination folder'),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(Icons.folder_open, color: palette.fg1, size: 18),
              tooltip: 'Browse…',
              onPressed: _pickDest,
            ),
          ]),
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
    );
  }

  Future<void> _pickDest() async {
    final dir =
        await ref.read(folderPickerProvider).pickFolder('Worktree folder');
    if (dir != null) _pathCtl.text = dir;
  }

  Future<void> _create() async {
    final path = _pathCtl.text.trim();
    if (path.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final newBranch = _branchCtl.text.trim();
    final existingRef = _refCtl.text.trim();
    final result = await ref.read(gitWriteOperationsProvider).addWorktree(
          widget.repo,
          path,
          newBranch: newBranch.isEmpty ? null : newBranch,
          ref: existingRef.isEmpty ? null : existingRef,
        );
    if (!mounted) return;
    switch (result) {
      case GitSuccess():
        Navigator.pop(context, true);
      case GitFailure(:final message):
        setState(() {
          _busy = false;
          _error = message;
        });
    }
  }
}
