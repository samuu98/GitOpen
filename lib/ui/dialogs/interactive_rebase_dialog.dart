import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
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
/// commit. Pure plan-builder: it returns the todo entries and the caller runs
/// the rebase through the git-actions controller.
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

  /// Shows the dialog. Returns the confirmed plan in git's todo order
  /// (oldest-first), or `null` if the user cancelled (or there was nothing
  /// to rebase).
  static Future<List<RebaseTodoEntry>?> show(
    BuildContext context, {
    required RepoLocation repo,
    required CommitSha onto,
  }) {
    return showDialog<List<RebaseTodoEntry>>(
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

  void _confirm() {
    final plan = _plan;
    if (plan == null || plan.isEmpty) return;
    // Dialog list is newest-first; git's todo list is oldest-first, so reverse.
    final entries = [
      for (final row in plan.reversed)
        RebaseTodoEntry(row.commit.sha, row.action),
    ];
    Navigator.pop(context, entries);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AppDialog(
      title: 'Interactive rebase',
      subtitle: 'Reorder, squash, fixup or drop commits on top of '
          '${widget.onto.short()}',
      width: 600,
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
                    onActionChanged: (a) => setState(() => plan[i].action = a),
                    onUp: () => _move(i, -1),
                    onDown: () => _move(i, 1),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      actions: [
        AppButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        AppButton.primary(
          label: 'Start rebase',
          icon: Icons.playlist_play,
          onPressed: (_plan == null || _plan!.isEmpty) ? null : _confirm,
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
    required this.onActionChanged,
    required this.onUp,
    required this.onDown,
  });
  final _PlanRow row;
  final AppPalette palette;
  final bool isFirst;
  final bool isLast;
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
                  onChanged: (a) {
                    if (a != null) onActionChanged(a);
                  },
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
            onPressed: isFirst ? null : onUp,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            color: palette.fg2,
            splashRadius: 14,
            tooltip: 'Move down',
            onPressed: isLast ? null : onDown,
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
