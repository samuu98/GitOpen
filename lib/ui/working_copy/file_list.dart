import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/files/path_tree.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/common/file_list_mode_toggle.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/discard_changes.dart';
import 'package:gitopen/ui/working_copy/file_row.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

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

class _FileListState extends ConsumerState<FileList> {
  final Set<String> _collapsedUnstaged = {};
  final Set<String> _collapsedStaged = {};

  @override
  Widget build(BuildContext context) {
    final asTree = ref.watch(
      appSettingsProvider.select((s) => s.fileListsAsTree),
    );
    final repo = widget.repo;
    final unstaged = widget.unstaged;
    final staged = widget.staged;
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [FileListModeToggle()],
          ),
        ),
        Header(
          title: 'Unstaged (${unstaged.length})',
          actions: [
            HeaderAction(
              'Discard all',
              unstaged.isEmpty
                  ? null
                  : () => confirmAndDiscardAll(context, ref, repo, unstaged),
              danger: true,
            ),
            HeaderAction(
              'Stage all',
              unstaged.isEmpty
                  ? null
                  : () async {
                      await ref
                          .read(gitWriteOperationsProvider)
                          .stageFiles(
                            repo,
                            unstaged.map((e) => e.path).toList(),
                          );
                      ref.invalidate(workingCopyStatusProvider(repo));
                    },
            ),
          ],
        ),
        ..._entryRows(
          unstaged,
          isStaged: false,
          asTree: asTree,
          collapsed: _collapsedUnstaged,
        ),
        Header(
          title: 'Staged (${staged.length})',
          actions: [
            HeaderAction(
              'Unstage all',
              staged.isEmpty
                  ? null
                  : () async {
                      await ref
                          .read(gitWriteOperationsProvider)
                          .unstageFiles(
                            repo,
                            staged.map((e) => e.path).toList(),
                          );
                      ref.invalidate(workingCopyStatusProvider(repo));
                    },
            ),
          ],
        ),
        ..._entryRows(
          staged,
          isStaged: true,
          asTree: asTree,
          collapsed: _collapsedStaged,
        ),
      ],
    );
  }

  List<Widget> _entryRows(
    List<WorkingFileEntry> entries, {
    required bool isStaged,
    required bool asTree,
    required Set<String> collapsed,
  }) {
    if (!asTree) {
      return [
        for (final e in entries)
          FileRow(repo: widget.repo, entry: e, isStaged: isStaged),
      ];
    }
    final nodes = buildFileTree(entries, (e) => e.path);
    return _nodeRows(nodes, isStaged: isStaged, depth: 0, collapsed: collapsed);
  }

  List<Widget> _nodeRows(
    List<PathTreeNode<WorkingFileEntry>> nodes, {
    required bool isStaged,
    required int depth,
    required Set<String> collapsed,
  }) {
    final rows = <Widget>[];
    for (final node in nodes) {
      final item = node.item;
      if (item != null) {
        rows.add(
          FileRow(
            repo: widget.repo,
            entry: item,
            isStaged: isStaged,
            displayName: node.name,
            indent: depth * 14.0,
          ),
        );
        continue;
      }
      final isCollapsed = collapsed.contains(node.path);
      rows.add(
        _DirRow(
          name: node.name,
          depth: depth,
          collapsed: isCollapsed,
          onTap: () => setState(() {
            if (!collapsed.add(node.path)) collapsed.remove(node.path);
          }),
        ),
      );
      if (!isCollapsed) {
        rows.addAll(
          _nodeRows(
            node.children,
            isStaged: isStaged,
            depth: depth + 1,
            collapsed: collapsed,
          ),
        );
      }
    }
    return rows;
  }
}

class _DirRow extends StatelessWidget {
  const _DirRow({
    required this.name,
    required this.depth,
    required this.collapsed,
    required this.onTap,
  });
  final String name;
  final int depth;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    return InkWell(
      onTap: onTap,
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
            TextButton(
              onPressed: a.onPressed,
              style: a.danger
                  ? TextButton.styleFrom(foregroundColor: palette.accentErr)
                  : null,
              child: Text(a.label),
            ),
        ],
      ),
    );
  }
}
