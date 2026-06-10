import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../application/repo_revision.dart';
import '../../domain/commits/commit_sha.dart';
import '../../domain/files/file_tree_entry.dart';
import '../../domain/repositories/repo_location.dart';
import '../common/app_context_menu.dart';
import '../common/skeleton.dart';
import '../dialogs/confirm_dialog.dart';
import '../dialogs/file_history_dialog.dart';
import '../theme/app_palette.dart';
import '../theme/app_typography.dart';

/// One directory level of the tree at a commit. Children are fetched lazily
/// when a folder is expanded, so huge repos only pay for what is visible.
final _fileTreeProvider = FutureProvider.family.autoDispose<List<FileTreeEntry>,
    ({RepoLocation repo, CommitSha sha, String path})>((ref, key) async {
  final git = ref.watch(gitReadOperationsProvider);
  return git.getFileTree(key.repo, key.sha, key.path);
});

/// Formats a byte count as a compact human-readable size (e.g. `1.4 MB`).
String _humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var size = bytes / 1024;
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(size >= 10 ? 0 : 1)} ${units[unit]}';
}

class FileTreeViewWidget extends ConsumerStatefulWidget {
  final RepoLocation repo;
  final CommitSha sha;
  const FileTreeViewWidget({super.key, required this.repo, required this.sha});

  @override
  ConsumerState<FileTreeViewWidget> createState() => _FileTreeViewState();
}

class _FileTreeViewState extends ConsumerState<FileTreeViewWidget> {
  final _expanded = <String>{};

  @override
  void didUpdateWidget(covariant FileTreeViewWidget old) {
    super.didUpdateWidget(old);
    if (old.sha != widget.sha || old.repo != widget.repo) _expanded.clear();
  }

  @override
  Widget build(BuildContext context) {
    return _DirectoryLevel(
      repo: widget.repo,
      sha: widget.sha,
      path: '',
      depth: 0,
      expanded: _expanded,
      onToggle: (path) => setState(() {
        _expanded.contains(path)
            ? _expanded.remove(path)
            : _expanded.add(path);
      }),
      asRoot: true,
    );
  }
}

class _DirectoryLevel extends ConsumerWidget {
  final RepoLocation repo;
  final CommitSha sha;
  final String path;
  final int depth;
  final Set<String> expanded;
  final ValueChanged<String> onToggle;
  final bool asRoot;

  const _DirectoryLevel({
    required this.repo,
    required this.sha,
    required this.path,
    required this.depth,
    required this.expanded,
    required this.onToggle,
    this.asRoot = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async =
        ref.watch(_fileTreeProvider((repo: repo, sha: sha, path: path)));
    return async.when(
      loading: () => asRoot
          ? const SkeletonList(rows: 12, rowHeight: 12)
          : Padding(
              padding: EdgeInsets.only(left: 20.0 + depth * 16, top: 4, bottom: 4),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5)),
              ),
            ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text('Error: $e', style: TextStyle(color: palette.accentErr)),
      ),
      data: (entries) {
        final sorted = [...entries]
          ..sort((a, b) {
            final aIsTree = a.kind == FileTreeKind.tree;
            final bIsTree = b.kind == FileTreeKind.tree;
            if (aIsTree != bIsTree) return aIsTree ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
        final rows = <Widget>[
          for (final e in sorted) ...[
            _EntryRow(
              repo: repo,
              sha: sha,
              entry: e,
              depth: depth,
              expanded: expanded.contains(e.fullPath),
              onToggle: onToggle,
            ),
            if (e.kind == FileTreeKind.tree && expanded.contains(e.fullPath))
              _DirectoryLevel(
                repo: repo,
                sha: sha,
                path: e.fullPath,
                depth: depth + 1,
                expanded: expanded,
                onToggle: onToggle,
              ),
          ],
        ];
        if (!asRoot) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
        }
        if (rows.isEmpty) {
          return Center(
              child: Text('Empty tree',
                  style: TextStyle(color: palette.fg2, fontSize: 12.5)));
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          children: rows,
        );
      },
    );
  }
}

class _EntryRow extends ConsumerWidget {
  final RepoLocation repo;
  final CommitSha sha;
  final FileTreeEntry entry;
  final int depth;
  final bool expanded;
  final ValueChanged<String> onToggle;

  const _EntryRow({
    required this.repo,
    required this.sha,
    required this.entry,
    required this.depth,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final typo = AppTypography.of(context);
    final e = entry;
    final isTree = e.kind == FileTreeKind.tree;
    final icon = isTree
        ? (expanded ? Icons.folder_open_outlined : Icons.folder_outlined)
        : e.kind == FileTreeKind.submodule
            ? Icons.developer_board_outlined
            : e.kind == FileTreeKind.symlink
                ? Icons.link_outlined
                : Icons.insert_drive_file_outlined;
    final iconColor = isTree ? palette.accentTag : palette.fg2;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: isTree ? () => onToggle(e.fullPath) : null,
        onSecondaryTapDown: e.kind == FileTreeKind.blob
            ? (d) => _showContextMenu(context, ref, d.globalPosition)
            : null,
        hoverColor: palette.bg3,
        child: Padding(
          padding: EdgeInsets.only(
              left: 8.0 + depth * 16, right: 8, top: 3, bottom: 3),
          child: Row(
            children: [
              if (isTree)
                Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: palette.fg3,
                )
              else
                const SizedBox(width: 14),
              const SizedBox(width: 2),
              Icon(icon, size: 15, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.name,
                  overflow: TextOverflow.ellipsis,
                  style: typo.body.copyWith(
                    color: palette.fg0,
                    fontWeight: isTree ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
              if (e.sizeBytes != null)
                Text(_humanSize(e.sizeBytes!),
                    style: typo.bodySmall.copyWith(
                      color: palette.fg3,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showContextMenu(
      BuildContext context, WidgetRef ref, Offset globalPos) async {
    final selected = await AppContextMenu.show<String>(
      context,
      globalPosition: globalPos,
      entries: const [
        AppMenuItem(value: 'history', label: 'File history…', icon: Icons.history),
        AppMenuItem(
            value: 'restore',
            label: 'Restore to working tree…',
            icon: Icons.settings_backup_restore),
        AppMenuDivider(),
        AppMenuItem(value: 'copy_path', label: 'Copy path', icon: Icons.copy_outlined),
      ],
    );
    if (selected == null || !context.mounted) return;
    switch (selected) {
      case 'history':
        await FileHistoryDialog.show(context, repo, entry.fullPath);
      case 'restore':
        final ok = await ConfirmDialog.show(
          context,
          title: 'Restore file',
          body: 'Replace "${entry.fullPath}" in the working tree with its '
              'content at ${sha.short()}?\n\nThe change stays unstaged so '
              'you can review it before committing.',
          confirmLabel: 'Restore',
        );
        if (!ok || !context.mounted) return;
        await ref
            .read(gitWriteOperationsProvider)
            .restoreFileAt(repo, sha, [entry.fullPath]);
        refreshRepo(ref, repo);
      case 'copy_path':
        await Clipboard.setData(ClipboardData(text: entry.fullPath));
    }
  }
}
