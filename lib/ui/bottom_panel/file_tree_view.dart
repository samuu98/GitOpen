import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/files/path_tree.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/files/file_tree_entry.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/bottom_panel/file_history_dialog.dart';
import 'package:gitopen/ui/common/app_icon_button.dart';
import 'package:gitopen/ui/common/file_list_mode_toggle.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final _fileTreeProvider = FutureProvider.family
    .autoDispose<List<FileTreeEntry>, ({RepoLocation repo, CommitSha sha})>((
      ref,
      key,
    ) async {
      final git = ref.watch(gitReadOperationsProvider);
      return git.getFileTree(key.repo, key.sha, '', recursive: true);
    });

/// The commit's full file listing, rendered as a collapsible folder tree or
/// a flat full-path list depending on the shared `fileListsAsTree` setting.
class FileTreeViewWidget extends ConsumerStatefulWidget {
  const FileTreeViewWidget({required this.repo, required this.sha, super.key});
  final RepoLocation repo;
  final CommitSha sha;

  @override
  ConsumerState<FileTreeViewWidget> createState() => _FileTreeViewWidgetState();
}

class _FileTreeViewWidgetState extends ConsumerState<FileTreeViewWidget> {
  final Set<String> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    final asTree = ref.watch(
      appSettingsProvider.select((s) => s.fileListsAsTree),
    );
    final async = ref.watch(
      _fileTreeProvider((repo: widget.repo, sha: widget.sha)),
    );
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e', style: TextStyle(color: palette.accentErr)),
      ),
      data: (entries) {
        final children = <Widget>[
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [FileListModeToggle()],
            ),
          ),
        ];
        if (asTree) {
          final nodes = buildFileTree(entries, (e) => e.fullPath);
          children.addAll(_nodeRows(nodes, depth: 0));
        } else {
          final sorted = [...entries]
            ..sort(
              (a, b) =>
                  a.fullPath.toLowerCase().compareTo(b.fullPath.toLowerCase()),
            );
          children.addAll([
            for (final e in sorted)
              _FileRow(repo: widget.repo, entry: e, label: e.fullPath),
          ]);
        }
        return ListView(padding: spacing.panel, children: children);
      },
    );
  }

  List<Widget> _nodeRows(
    List<PathTreeNode<FileTreeEntry>> nodes, {
    required int depth,
  }) {
    final rows = <Widget>[];
    for (final node in nodes) {
      final item = node.item;
      if (item != null) {
        rows.add(
          _FileRow(
            repo: widget.repo,
            entry: item,
            label: node.name,
            indent: depth * 14.0,
          ),
        );
        continue;
      }
      final isCollapsed = _collapsed.contains(node.path);
      rows.add(
        _FolderRow(
          name: node.name,
          depth: depth,
          collapsed: isCollapsed,
          onTap: () => setState(() {
            if (!_collapsed.add(node.path)) _collapsed.remove(node.path);
          }),
        ),
      );
      if (!isCollapsed) {
        rows.addAll(_nodeRows(node.children, depth: depth + 1));
      }
    }
    return rows;
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
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
          left: 8 + depth * 14.0,
          right: 8,
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
            Icon(Icons.folder_outlined, size: 15, color: palette.accentTag),
            SizedBox(width: spacing.sm),
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

/// A single file row (blob/symlink/submodule — the recursive listing has no
/// tree rows). Exposes a "File history" affordance (hover icon +
/// right-click menu) that opens [FileHistoryDialog].
class _FileRow extends StatefulWidget {
  const _FileRow({
    required this.repo,
    required this.entry,
    required this.label,
    this.indent = 0,
  });
  final RepoLocation repo;
  final FileTreeEntry entry;
  final String label;
  final double indent;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hover = false;

  Future<void> _openHistory() => FileHistoryDialog.show(
    context,
    repo: widget.repo,
    path: widget.entry.fullPath,
  );

  Future<void> _showMenu(Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem<String>(
          value: 'history',
          height: 36,
          child: Text('File history', style: TextStyle(fontSize: 12.5)),
        ),
      ],
    );
    if (selected == 'history') await _openHistory();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    final e = widget.entry;
    final icon = e.kind == FileTreeKind.submodule
        ? Icons.developer_board_outlined
        : e.kind == FileTreeKind.symlink
        ? Icons.link_outlined
        : Icons.insert_drive_file_outlined;

    final row = Padding(
      padding: EdgeInsets.only(
        left: 8 + widget.indent,
        right: 8,
        top: 3,
        bottom: 3,
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: palette.fg2),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(
              widget.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.fg0, fontSize: 12.5),
            ),
          ),
          if (_hover)
            _HistoryButton(onPressed: _openHistory)
          else if (e.sizeBytes != null)
            Text(
              '${e.sizeBytes}',
              style: TextStyle(
                color: palette.fg3,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onSecondaryTapDown: (d) => _showMenu(d.globalPosition),
        child: Material(
          color: _hover ? palette.bg2 : Colors.transparent,
          child: row,
        ),
      ),
    );
  }
}

class _HistoryButton extends StatelessWidget {
  const _HistoryButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      icon: Icons.history,
      tooltip: 'File history',
      onPressed: onPressed,
    );
  }
}
