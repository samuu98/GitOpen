import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/branch_deletion.dart';
import 'package:gitopen/application/git/branch_deletion_flow.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// What the user chose to delete in [DeleteBranchDialog].
class DeleteBranchSelection {
  const DeleteBranchSelection({
    required this.deleteLocal,
    required this.deleteRemote,
  });
  final bool deleteLocal;
  final bool deleteRemote;

  bool get any => deleteLocal || deleteRemote;
}

/// Confirms deletion of a branch's local and/or remote side. Each present side
/// is a checkbox, checked by default; the local side is disabled when it is the
/// checked-out branch.
class DeleteBranchDialog extends StatefulWidget {
  const DeleteBranchDialog({required this.targets, super.key});
  final BranchDeletionTargets targets;

  static Future<DeleteBranchSelection?> show(
    BuildContext context, {
    required BranchDeletionTargets targets,
  }) {
    return showDialog<DeleteBranchSelection>(
      context: context,
      builder: (_) => DeleteBranchDialog(targets: targets),
    );
  }

  @override
  State<DeleteBranchDialog> createState() => _DeleteBranchDialogState();
}

class _DeleteBranchDialogState extends State<DeleteBranchDialog> {
  late bool _local =
      widget.targets.localName != null && !widget.targets.localIsCurrent;
  late bool _remote = widget.targets.remoteRef != null;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final t = widget.targets;
    return AppDialog(
      title: 'Delete branch',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t.localName != null)
            CheckboxListTile(
              value: _local,
              onChanged: t.localIsCurrent
                  ? null
                  : (v) => setState(() => _local = v ?? false),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Local branch ${t.localName}',
                style: TextStyle(color: palette.fg0, fontSize: 13),
              ),
              subtitle: t.localIsCurrent
                  ? Text(
                      'Current branch — checkout another first',
                      style: TextStyle(color: palette.fg3, fontSize: 11),
                    )
                  : null,
            ),
          if (t.remoteRef != null)
            CheckboxListTile(
              value: _remote,
              onChanged: (v) => setState(() => _remote = v ?? false),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Remote branch ${t.remoteRef}',
                style: TextStyle(color: palette.fg0, fontSize: 13),
              ),
              subtitle: Text(
                'Deletes it on the server (push --delete)',
                style: TextStyle(color: palette.fg3, fontSize: 11),
              ),
            ),
        ],
      ),
      actions: [
        AppButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        AppButton.danger(
          label: 'Delete',
          onPressed: (_local || _remote)
              ? () => Navigator.pop(
                  context,
                  DeleteBranchSelection(
                    deleteLocal: _local,
                    deleteRemote: _remote,
                  ),
                )
              : null,
        ),
      ],
    );
  }
}

/// Keeps confirmation, progress and per-branch failures in the same modal.
class DeleteBranchesDialog extends ConsumerStatefulWidget {
  const DeleteBranchesDialog({
    required this.repo,
    required this.branches,
    required this.allBranches,
    super.key,
  });

  final RepoLocation repo;
  final List<Branch> branches;
  final List<Branch> allBranches;

  static Future<void> show(
    BuildContext context, {
    required RepoLocation repo,
    required List<Branch> branches,
    required List<Branch> allBranches,
  }) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DeleteBranchesDialog(
      repo: repo,
      branches: branches,
      allBranches: allBranches,
    ),
  );

  @override
  ConsumerState<DeleteBranchesDialog> createState() => _DeleteBranchesState();
}

class _DeleteEntry {
  _DeleteEntry(
    this.name, {
    required this.remote,
    required this.current,
    bool selected = true,
  }) : selected = selected && !current;

  final String name;
  final bool remote;
  final bool current;
  bool selected;
  bool removeWorktree = false;

  /// Set when the last run ended with git refusing `branch -d`, so the row
  /// keeps offering force after a partial outcome.
  bool needsForce = false;
  BranchDeleteStatus? status;
  String? inspectError;
}

class _DeleteBranchesState extends ConsumerState<DeleteBranchesDialog> {
  late final List<_DeleteEntry> _entries = _makeEntries();
  bool _loading = true;
  bool _busy = false;
  bool _forceBranch = false;
  int _done = 0;
  int _total = 0;
  List<BranchDeleteResult>? _results;
  String? _error;

  List<_DeleteEntry> _makeEntries() {
    final entries = <String, _DeleteEntry>{};
    for (final branch in widget.branches) {
      final targets = branchDeletionTargets(branch, widget.allBranches);
      if (targets.localName case final name?) {
        entries.putIfAbsent(
          'local:$name',
          () => _DeleteEntry(
            name,
            remote: false,
            current: targets.localIsCurrent,
          ),
        );
      }
      if (targets.remoteRef case final name?) {
        entries.putIfAbsent(
          'remote:$name',
          // A server-side delete is opt-in in a batch unless the user picked
          // the remote row itself; a single branch keeps both sides checked.
          () => _DeleteEntry(
            name,
            remote: true,
            current: false,
            selected: branch.isRemote || widget.branches.length == 1,
          ),
        );
      }
    }
    return entries.values.toList();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final flow = ref.read(branchDeletionFlowProvider);
    for (final entry in _entries.where((e) => !e.remote)) {
      try {
        final status = await flow.inspect(widget.repo, entry.name);
        entry.status = status;
        if (status.isMainWorktree || status.worktreeLocked) {
          entry.selected = false;
        }
      } on Object catch (e) {
        entry
          ..inspectError = e.toString()
          ..selected = false;
      }
      if (mounted) setState(() {});
    }
    if (mounted) setState(() => _loading = false);
  }

  /// True once a run left a branch git refused: the dialog stays interactive
  /// for exactly that retry instead of ending on a dead result list.
  bool get _canRetry => _entries.any((e) => e.needsForce);

  /// Rows and checkboxes are frozen while a run is in flight and after a final
  /// result — but not when a refused branch can still be force deleted.
  bool get _locked => _busy || (_results != null && !_canRetry);

  /// After a result only a refused branch can be picked again: every other
  /// row is already deleted or reported.
  bool _frozen(_DeleteEntry e) => _busy || (_results != null && !e.needsForce);

  bool _blocked(_DeleteEntry e) =>
      e.current ||
      e.inspectError != null ||
      e.status?.isMainWorktree == true ||
      e.status?.worktreeLocked == true;

  /// A selected row that would only fail as configured does not count.
  bool _ready(_DeleteEntry e) {
    if (e.remote) return true;
    final state = e.status;
    if (state == null || !state.exists) return false;
    if (e.needsForce && !_forceBranch) return false;
    return (state.merged || _forceBranch) &&
        (state.worktreePath == null || e.removeWorktree);
  }

  String _status(_DeleteEntry e) {
    if (e.inspectError != null) return e.inspectError!;
    if (e.current) return 'Current branch — skipped';
    if (e.status?.isMainWorktree == true) {
      return 'Checked out in the main worktree — skipped';
    }
    if (e.status?.worktreeLocked == true) return 'Locked worktree — skipped';
    if (e.remote) return 'Remote branch on the server';
    final state = e.status;
    if (state == null) return 'Checking branch…';
    if (!state.exists) return 'Branch no longer exists';
    final details = <String>[
      if (!state.merged || e.needsForce) 'Unmerged — force delete required',
      if (state.worktreePath != null) 'Checked out in ${state.worktreePath}',
      if (state.worktreeDirty)
        'Uncommitted or untracked changes will be lost if removed',
    ];
    return details.isEmpty ? 'Merged branch' : details.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final count = widget.branches.length;
    return AppDialog(
      title: count == 1 ? 'Delete branch?' : 'Delete $count branches?',
      subtitle: 'Review each branch before deleting',
      width: 570,
      busy: _busy || _loading,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in _entries) ...[
            AppInteractiveSurface(
              onTap: _frozen(entry) || _blocked(entry)
                  ? null
                  : () => setState(() => entry.selected = !entry.selected),
              selected: entry.selected,
              semanticLabel: 'Delete ${entry.name}',
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
              child: (context, visual) => Row(
                children: [
                  Icon(
                    entry.selected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    color: visual.foreground,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.name, style: TextStyle(color: palette.fg0)),
                        Text(
                          _status(entry),
                          style: TextStyle(color: palette.fg2, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (entry.selected &&
                entry.status?.worktreePath != null &&
                !_blocked(entry))
              AppInteractiveSurface(
                onTap: _frozen(entry)
                    ? null
                    : () => setState(
                        () => entry.removeWorktree = !entry.removeWorktree,
                      ),
                selected: entry.removeWorktree,
                semanticLabel: 'Also remove the worktree for ${entry.name}',
                padding: const EdgeInsets.only(left: 34, top: 3, bottom: 6),
                child: (context, visual) => Row(
                  children: [
                    Icon(
                      entry.removeWorktree
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color: visual.foreground,
                      size: 17,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Also remove the worktree',
                      style: TextStyle(color: visual.foreground, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
          if (_entries.any(
            (e) => !e.remote && (e.status?.merged == false || e.needsForce),
          ))
            AppInteractiveSurface(
              onTap: _locked
                  ? null
                  : () => setState(
                      () => _forceBranch = !_forceBranch,
                    ),
              selected: _forceBranch,
              semanticLabel: 'Force delete unmerged branches',
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: (context, visual) => Row(
                children: [
                  Icon(
                    _forceBranch
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                    color: visual.foreground,
                    size: 17,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Force delete unmerged branches',
                    style: TextStyle(color: visual.foreground, fontSize: 12),
                  ),
                ],
              ),
            ),
          if (_busy)
            Text(
              'Deleting $_done of $_total…',
              style: TextStyle(color: palette.fg1),
            ),
          if (_error != null)
            Text(_error!, style: TextStyle(color: palette.accentErr)),
          if (_results case final results?) ...[
            const SizedBox(height: 8),
            Text(
              'Deleted ${results.where((r) => r.error == null).length} '
              'of ${results.length} branches',
              style: TextStyle(color: palette.fg0),
            ),
            for (final result in results.where((r) => r.error != null))
              Text(
                '${result.name}: '
                '${result.worktreeRemoved ? 'Worktree removed. ' : ''}'
                '${result.error}',
                style: TextStyle(color: palette.accentErr, fontSize: 11.5),
              ),
          ],
        ],
      ),
      actions: [
        AppButton.secondary(
          label: _results == null ? 'Cancel' : 'Close',
          onPressed: _busy ? null : () => Navigator.pop(context),
          autofocus: true,
        ),
        // A refused branch keeps the action available: the force option above
        // is only an offer if the user can act on it.
        if (_results == null || _entries.any((e) => e.needsForce))
          AppButton.danger(
            label: count == 1 ? 'Delete' : 'Delete $count branches',
            onPressed:
                _busy ||
                    _loading ||
                    !_entries.any((e) => e.selected && _ready(e))
                ? null
                : _run,
          ),
      ],
    );
  }

  Future<void> _run() async {
    final selected = _entries.where((e) => e.selected).toList();
    final unmerged = selected
        .where((e) => !e.remote && (e.status?.merged == false || e.needsForce))
        .toList();
    if (_forceBranch && unmerged.isNotEmpty) {
      final names = unmerged.map((e) => e.name).join(', ');
      final confirmed = await ConfirmDialog.show(
        context,
        title: unmerged.length == 1
            ? 'Force delete branch?'
            : 'Force delete branches?',
        body: 'Unmerged commits on $names will be lost.',
        confirmLabel: 'Force delete',
        dangerous: true,
      );
      if (!confirmed || !mounted) return;
    }
    final dirty = selected
        .where((e) => e.removeWorktree && e.status?.worktreeDirty == true)
        .toList();
    var forceWorktree = false;
    if (dirty.isNotEmpty) {
      final paths = dirty
          .map((e) => '${e.name}: ${e.status!.worktreePath}')
          .join('\n');
      forceWorktree = await ConfirmDialog.show(
        context,
        title: 'Force remove dirty worktree?',
        body:
            'Uncommitted changes and untracked files will be lost in:\n'
            '$paths',
        confirmLabel: 'Force remove',
        dangerous: true,
      );
      if (!forceWorktree || !mounted) {
        return;
      }
    }
    setState(() {
      _busy = true;
      _done = 0;
      _total = selected.length;
      _results = null;
      _error = null;
    });
    final requests = [
      for (final entry in selected)
        BranchDeleteRequest(
          entry.name,
          remote: entry.remote,
          forceBranch: _forceBranch,
          removeWorktree: entry.removeWorktree,
          forceWorktree: forceWorktree && entry.status?.worktreeDirty == true,
        ),
    ];
    final run = await ref
        .read(gitActionsControllerProvider)
        .deleteBranches(
          context,
          widget.repo,
          requests,
          onProgress: (done, total) {
            if (mounted) {
              setState(() {
                _done = done;
                _total = total;
              });
            }
          },
        );
    if (!mounted) {
      return;
    }
    final results = run.value ?? const <BranchDeleteResult>[];
    for (final entry in _entries) {
      final result = results.where((r) => r.name == entry.name).firstOrNull;
      if (result == null) continue;
      // Only a branch git refused stays selected: the retry is the force
      // delete, not a second attempt at everything.
      entry
        ..needsForce = result.needsForce
        ..selected = result.needsForce;
    }
    setState(() {
      _busy = false;
      _results = run.value;
      // A refresh failure is the runner's toast, not a second message here.
      if (run.status == ActionRunStatus.skipped) {
        _error = 'A deletion is already running.';
      }
      // What the refused rows say must match what git now sees: the worktree
      // of a refused branch is already gone.
      if (_canRetry) _loading = true;
    });
    if (_canRetry) unawaited(_load());
  }
}
