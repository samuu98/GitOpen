import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/files/file_tree_entry.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/bottom_panel/file_history_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final AutoDisposeFutureProviderFamily<List<FileTreeEntry>,
        ({RepoLocation repo, CommitSha sha})> _fileTreeProvider =
    FutureProvider.family.autoDispose<List<FileTreeEntry>,
        ({RepoLocation repo, CommitSha sha})>((ref, key) async {
  final git = ref.watch(gitReadOperationsProvider);
  return git.getFileTree(key.repo, key.sha, '');
});

class FileTreeViewWidget extends ConsumerWidget {
  const FileTreeViewWidget({required this.repo, required this.sha, super.key});
  final RepoLocation repo;
  final CommitSha sha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(_fileTreeProvider((repo: repo, sha: sha)));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e',
          style: TextStyle(color: palette.accentErr))),
      data: (entries) {
        final sorted = [...entries]
          ..sort((a, b) {
            final aIsTree = a.kind == FileTreeKind.tree;
            final bIsTree = b.kind == FileTreeKind.tree;
            if (aIsTree != bIsTree) return aIsTree ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: sorted.length,
          itemBuilder: (_, i) => _FileRow(repo: repo, entry: sorted[i]),
        );
      },
    );
  }
}

/// A single file-tree row.  Visuals are unchanged from the prior inline
/// builder; blob/symlink/submodule rows additionally expose a "File history"
/// affordance (hover icon + right-click menu) that opens [FileHistoryDialog].
/// Tree (folder) rows are left exactly as before.
class _FileRow extends StatefulWidget {
  const _FileRow({required this.repo, required this.entry});
  final RepoLocation repo;
  final FileTreeEntry entry;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hover = false;

  bool get _isFile => widget.entry.kind != FileTreeKind.tree;

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
    final e = widget.entry;
    final icon = e.kind == FileTreeKind.tree
        ? Icons.folder_outlined
        : e.kind == FileTreeKind.submodule
            ? Icons.developer_board_outlined
            : e.kind == FileTreeKind.symlink
                ? Icons.link_outlined
                : Icons.insert_drive_file_outlined;
    final iconColor =
        e.kind == FileTreeKind.tree ? palette.accentTag : palette.fg2;

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
      child: Row(
        children: [
          Icon(icon, size: 15, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              e.name,
              style: TextStyle(
                color: palette.fg0,
                fontSize: 12.5,
                fontWeight: e.kind == FileTreeKind.tree
                    ? FontWeight.w500
                    : FontWeight.normal,
              ),
            ),
          ),
          if (_isFile && _hover)
            _HistoryButton(onPressed: _openHistory)
          else if (e.sizeBytes != null)
            Text('${e.sizeBytes}',
                style: TextStyle(
                  color: palette.fg3,
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                )),
        ],
      ),
    );

    if (!_isFile) return row;

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
    final palette = AppPalette.of(context);
    return Tooltip(
      message: 'File history',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(Icons.history, size: 15, color: palette.fg2),
        ),
      ),
    );
  }
}
