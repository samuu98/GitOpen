import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/files/path_tree.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/common/app_animated_row.dart';
import 'package:gitopen/ui/common/file_list_mode_toggle.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/operations/action_feedback.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/discard_changes.dart';
import 'package:gitopen/ui/working_copy/file_row.dart';

class FileList extends ConsumerStatefulWidget {
  const FileList({
    required this.repo,
    required this.unstaged,
    required this.staged,
    super.key,
  });
  final RepoLocation repo;
  final List<WorkingFileEntry> unstaged;
  final List<WorkingFileEntry> staged;

  @override
  ConsumerState<FileList> createState() => _FileListState();
}

typedef _VisibleNode = ({PathTreeNode<WorkingFileEntry> node, int depth});

class _FileListState extends ConsumerState<FileList> {
  final Set<String> _collapsedUnstaged = {};
  final Set<String> _collapsedStaged = {};
  bool _writing = false;

  Future<void> _writeAll({required bool stage}) async {
    if (_writing) return;
    setState(() => _writing = true);
    try {
      final repo = widget.repo;
      final write = ref.read(gitWriteOperationsProvider);
      final run = await ref
          .read(actionRunnerProvider)
          .runAndRefresh<GitResult<void>>(
            key: 'working-copy:all',
            repo: repo,
            scopes: const {RefreshScope.status, RefreshScope.workingCopy},
            failed: (value) => value is GitFailure<void>,
            label: stage ? 'Stage all' : 'Unstage all',
            action: () => stage
                ? write.stageFiles(
                    repo,
                    widget.unstaged.map((e) => e.path).toList(),
                  )
                : write.unstageFiles(
                    repo,
                    widget.staged.map((e) => e.path).toList(),
                  ),
          );
      if (run.value case final GitFailure<void> failure) {
        ref
            .read(actionFeedbackProvider)
            .showActionFailure(
              '${stage ? 'Stage' : 'Unstage'} failed: ${failure.message}',
            );
      }
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  Future<void> _discardAll() async {
    if (_writing) return;
    setState(() => _writing = true);
    try {
      await confirmAndDiscardAll(
        context,
        ref,
        widget.repo,
        widget.unstaged,
      );
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asTree = ref.watch(
      appSettingsProvider.select((s) => s.fileListsAsTree),
    );
    final unstaged = widget.unstaged;
    final staged = widget.staged;
    final unstagedTree = asTree
        ? _visibleNodes(unstaged, _collapsedUnstaged)
        : null;
    final stagedTree = asTree ? _visibleNodes(staged, _collapsedStaged) : null;
    final unstagedCount = unstagedTree?.length ?? unstaged.length;
    final stagedCount = stagedTree?.length ?? staged.length;
    final stagedHeader = unstagedCount + 2;
    return ListView.builder(
      itemCount: stagedHeader + 1 + stagedCount,
      itemBuilder: (context, index) {
        if (index == 0) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [FileListModeToggle()],
            ),
          );
        }
        if (index == 1) {
          return Header(
            title: 'Unstaged (${unstaged.length})',
            actions: [
              HeaderAction(
                'Discard all',
                unstaged.isEmpty || _writing ? null : _discardAll,
                danger: true,
              ),
              HeaderAction(
                'Stage all',
                unstaged.isEmpty || _writing
                    ? null
                    : () => _writeAll(stage: true),
              ),
            ],
          );
        }
        if (index < stagedHeader) {
          return _entryRow(
            unstaged,
            unstagedTree,
            index - 2,
            isStaged: false,
            collapsed: _collapsedUnstaged,
          );
        }
        if (index == stagedHeader) {
          return Header(
            title: 'Staged (${staged.length})',
            actions: [
              HeaderAction(
                'Unstage all',
                staged.isEmpty || _writing
                    ? null
                    : () => _writeAll(stage: false),
              ),
            ],
          );
        }
        return _entryRow(
          staged,
          stagedTree,
          index - stagedHeader - 1,
          isStaged: true,
          collapsed: _collapsedStaged,
        );
      },
    );
  }

  List<_VisibleNode> _visibleNodes(
    List<WorkingFileEntry> entries,
    Set<String> collapsed,
  ) {
    final rows = <_VisibleNode>[];
    void visit(List<PathTreeNode<WorkingFileEntry>> nodes, int depth) {
      for (final node in nodes) {
        rows.add((node: node, depth: depth));
        if (node.item == null && !collapsed.contains(node.path)) {
          visit(node.children, depth + 1);
        }
      }
    }

    visit(buildFileTree(entries, (e) => e.path), 0);
    return rows;
  }

  Widget _entryRow(
    List<WorkingFileEntry> entries,
    List<_VisibleNode>? tree,
    int index, {
    required bool isStaged,
    required Set<String> collapsed,
  }) {
    if (tree == null) {
      final entry = entries[index];
      return FileRow(
        key: ValueKey('${isStaged ? 's' : 'u'}:${entry.path}'),
        repo: widget.repo,
        entry: entry,
        isStaged: isStaged,
      );
    }
    final (:node, :depth) = tree[index];
    final item = node.item;
    if (item != null) {
      return FileRow(
        key: ValueKey('${isStaged ? 's' : 'u'}:${item.path}'),
        repo: widget.repo,
        entry: item,
        isStaged: isStaged,
        displayName: node.name,
        indent: depth * 14.0,
      );
    }
    return _DirRow(
      key: ValueKey('${isStaged ? 's' : 'u'}:${node.path}'),
      name: node.name,
      depth: depth,
      collapsed: collapsed.contains(node.path),
      onTap: () => setState(() {
        if (!collapsed.add(node.path)) collapsed.remove(node.path);
      }),
    );
  }
}

class _DirRow extends StatelessWidget {
  const _DirRow({
    required this.name,
    required this.depth,
    required this.collapsed,
    required this.onTap,
    super.key,
  });
  final String name;
  final int depth;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    return AppAnimatedRow(
      selected: false,
      onTap: onTap,
      tooltip: collapsed ? 'Expand folder $name' : 'Collapse folder $name',
      padding: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.only(
          left: 12 + depth * 14.0,
          right: 12,
          top: 3,
          bottom: 3,
        ),
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 14,
              color: palette.fg3,
            ),
            SizedBox(width: spacing.xxs),
            Icon(Icons.folder_outlined, size: 14, color: palette.accentTag),
            SizedBox(width: spacing.xs),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.fg1,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class HeaderAction {
  const HeaderAction(this.label, this.onPressed, {this.danger = false});
  final String label;
  final VoidCallback? onPressed;
  final bool danger;
}

class Header extends StatelessWidget {
  const Header({required this.title, this.actions = const [], super.key});
  final String title;
  final List<HeaderAction> actions;
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.md,
        vertical: spacing.xs,
      ),
      color: palette.bg2,
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: palette.fg1,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          for (final a in actions)
            AppButton(
              label: a.label,
              onPressed: a.onPressed,
              compact: true,
              kind: a.danger ? AppButtonKind.danger : AppButtonKind.secondary,
            ),
        ],
      ),
    );
  }
}
