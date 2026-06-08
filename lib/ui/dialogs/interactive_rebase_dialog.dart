import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// A row in the editable rebase plan: a commit plus the chosen action.
/// The list is held NEWEST-FIRST in the dialog (matching the graph) and only
/// reversed to git's oldest-first todo order when the rebase is launched.
class _PlanRow {
  _PlanRow(this.commit, this.action);
  final CommitInfo commit;
  RebaseTodoAction action;
}

/// Lets the user reorder / squash / fixup / drop the commits on top of a base
/// commit, then runs a scripted (non-interactive) `git rebase -i`.
///
/// [onto] is the base commit the plan is replayed onto (the commit the user
/// right-clicked). The plan is every commit in `onto..HEAD`.
class InteractiveRebaseDialog extends ConsumerStatefulWidget {
  const InteractiveRebaseDialog({
    required this.repo,
    required this.onto,
    super.key,
  });
  final RepoLocation repo;
  final CommitSha onto;

  /// Shows the dialog. Returns the [RebaseOutcome] on a started rebase, or
  /// `null` if the user cancelled (or there was nothing to rebase).
  static Future<RebaseOutcome?> show(
    BuildContext context, {
    required RepoLocation repo,
    required CommitSha onto,
  }) {
    return showDialog<RebaseOutcome>(
      context: context,
      builder: (_) => InteractiveRebaseDialog(repo: repo, onto: onto),
    );
  }

  @override
  ConsumerState<InteractiveRebaseDialog> createState() =>
      _InteractiveRebaseDialogState();
}

class _InteractiveRebaseDialogState
    extends ConsumerState<InteractiveRebaseDialog> {
  late final Future<List<CommitInfo>> _commitsFuture;
  List<_PlanRow>? _plan;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _commitsFuture = _loadCommits();
  }

  /// Commits in `onto..HEAD`, newest-first (git's default log order).
  Future<List<CommitInfo>> _loadCommits() {
    final git = ref.read(gitReadOperationsProvider);
    return git
        .getCommits(
          widget.repo,
          CommitQuery(refSpec: '${widget.onto.value}..HEAD'),
        )
        .toList();
  }

  void _ensurePlan(List<CommitInfo> commits) {
    _plan ??= [
      for (final c in commits) _PlanRow(c, RebaseTodoAction.pick),
    ];
  }

  void _move(int index, int delta) {
    final plan = _plan;
    if (plan == null) return;
    final target = index + delta;
    if (target < 0 || target >= plan.length) return;
    setState(() {
      final row = plan.removeAt(index);
      plan.insert(target, row);
    });
  }

  Future<void> _start() async {
    final plan = _plan;
    if (plan == null || plan.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Dialog list is newest-first; git's todo list is oldest-first, so reverse.
    final entries = [
      for (final row in plan.reversed)
        RebaseTodoEntry(row.commit.sha, row.action),
    ];
    final write = ref.read(gitWriteOperationsProvider);
    final result =
        await write.interactiveRebase(widget.repo, widget.onto, entries);
    if (!mounted) return;
    switch (result) {
      case GitSuccess(:final value):
        Navigator.pop(context, value);
      case GitFailure(:final message):
        setState(() {
          _busy = false;
          _error = message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AppDialog(
      title: 'Interactive rebase',
      subtitle: 'Reorder, squash, fixup or drop commits on top of '
          '${widget.onto.short()}',
      width: 600,
      busy: _busy,
      content: FutureBuilder<List<CommitInfo>>(
        future: _commitsFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snap.hasError) {
            return SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  'Failed to load commits: ${snap.error}',
                  style: TextStyle(color: palette.accentErr, fontSize: 12.5),
                ),
              ),
            );
          }
          final commits = snap.data ?? const <CommitInfo>[];
          if (commits.isEmpty) {
            return SizedBox(
              height: 80,
              child: Center(
                child: Text(
                  'No commits between ${widget.onto.short()} and HEAD.',
                  style: TextStyle(color: palette.fg2, fontSize: 12.5),
                ),
              ),
            );
          }
          _ensurePlan(commits);
          final plan = _plan!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Newest first. squash/fixup fold a commit into the one below '
                'it.',
                style: TextStyle(color: palette.fg2, fontSize: 11.5),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: plan.length,
                  separatorBuilder: (_, _) =>
                      Divider(height: 1, color: palette.border),
                  itemBuilder: (context, i) => _PlanRowTile(
                    row: plan[i],
                    palette: palette,
                    isFirst: i == 0,
                    isLast: i == plan.length - 1,
                    enabled: !_busy,
                    onActionChanged: (a) => setState(() => plan[i].action = a),
                    onUp: () => _move(i, -1),
                    onDown: () => _move(i, 1),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.error_outline,
                        size: 16, color: palette.accentErr),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _error!,
                        style:
                            TextStyle(color: palette.accentErr, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
      actions: [
        AppButton.secondary(
          label: 'Cancel',
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
        AppButton.primary(
          label: 'Start rebase',
          icon: Icons.playlist_play,
          onPressed: (_busy || _plan == null || _plan!.isEmpty) ? null : _start,
        ),
      ],
    );
  }
}

class _PlanRowTile extends StatelessWidget {
  const _PlanRowTile({
    required this.row,
    required this.palette,
    required this.isFirst,
    required this.isLast,
    required this.enabled,
    required this.onActionChanged,
    required this.onUp,
    required this.onDown,
  });
  final _PlanRow row;
  final AppPalette palette;
  final bool isFirst;
  final bool isLast;
  final bool enabled;
  final ValueChanged<RebaseTodoAction> onActionChanged;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    final dropped = row.action == RebaseTodoAction.drop;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 132,
            child: Container(
              decoration: BoxDecoration(
                color: palette.bg1,
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<RebaseTodoAction>(
                  value: row.action,
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: palette.bg2,
                  style: TextStyle(color: palette.fg0, fontSize: 12.5),
                  iconEnabledColor: palette.fg2,
                  items: RebaseTodoAction.values
                      .map((a) => DropdownMenuItem(
                            value: a,
                            child: Text(_actionLabel(a)),
                          ))
                      .toList(),
                  onChanged: enabled
                      ? (a) {
                          if (a != null) onActionChanged(a);
                        }
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            row.commit.sha.short(),
            style: TextStyle(
              color: palette.fg2,
              fontSize: 11.5,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.commit.summary,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: dropped ? palette.fg3 : palette.fg0,
                fontSize: 12.5,
                decoration:
                    dropped ? TextDecoration.lineThrough : TextDecoration.none,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up, size: 18),
            color: palette.fg2,
            splashRadius: 14,
            tooltip: 'Move up',
            onPressed: (enabled && !isFirst) ? onUp : null,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            color: palette.fg2,
            splashRadius: 14,
            tooltip: 'Move down',
            onPressed: (enabled && !isLast) ? onDown : null,
          ),
        ],
      ),
    );
  }
}

String _actionLabel(RebaseTodoAction a) => switch (a) {
      RebaseTodoAction.pick => 'pick',
      RebaseTodoAction.squash => 'squash',
      RebaseTodoAction.fixup => 'fixup',
      RebaseTodoAction.drop => 'drop',
    };
