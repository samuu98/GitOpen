import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/ui/dialogs/clone_dialog.dart';
import 'package:gitopen/ui/shell/repo_tree_row.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// One rendered line of the (possibly collapsed) tree: a node, its [depth],
/// and where it sits among its siblings ([parentId] + [indexInParent]) so a
/// drop can be turned into a `moveRepo`/`moveFolder` call.
class VisibleRow {
  const VisibleRow({
    required this.node,
    required this.depth,
    required this.parentId,
    required this.indexInParent,
  });
  final RepoTreeNode node;
  final int depth;
  final FolderId? parentId;
  final int indexInParent;
}

/// Pre-order walk of the tree, skipping the descendants of collapsed folders.
List<VisibleRow> flattenVisible(List<RepoTreeNode> roots) {
  final out = <VisibleRow>[];
  void walk(List<RepoTreeNode> nodes, int depth, FolderId? parentId) {
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      out.add(
        VisibleRow(
          node: n,
          depth: depth,
          parentId: parentId,
          indexInParent: i,
        ),
      );
      if (n is FolderNode && !n.folder.collapsed) {
        walk(n.children, depth + 1, n.folder.id);
      }
    }
  }

  walk(roots, 0, null);
  return out;
}

/// The dropdown body: a scrollable folder/repo tree plus footer actions.
class RepoTreePopover extends ConsumerStatefulWidget {
  const RepoTreePopover({required this.onDismiss, super.key});
  final VoidCallback onDismiss;

  @override
  ConsumerState<RepoTreePopover> createState() => _RepoTreePopoverState();
}

class _RepoTreePopoverState extends ConsumerState<RepoTreePopover> {
  final TextEditingController _newFolder = TextEditingController();
  bool _addingFolder = false;

  @override
  void dispose() {
    _newFolder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final tree = ref.watch(repoOrganizerProvider);
    final activeId = ref.watch(activeWorkspaceIdProvider);
    final rows = flattenVisible(tree);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 340,
        constraints: const BoxConstraints(maxHeight: 480),
        decoration: BoxDecoration(
          color: palette.bg2,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 8, spreadRadius: 1),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: rows.isEmpty
                  ? _empty(palette)
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: rows.length,
                      itemBuilder: (context, i) => _rowFor(rows[i], activeId),
                    ),
            ),
            Divider(height: 1, color: palette.border),
            if (_addingFolder) _newFolderField(palette),
            _footer(palette),
          ],
        ),
      ),
    );
  }

  Widget _rowFor(VisibleRow row, RepoId? activeId) {
    final node = row.node;
    if (node is FolderNode) {
      return FolderRow(folder: node.folder, depth: row.depth);
    }
    node as RepoNode;
    return RepoRow(
      location: node.location,
      depth: row.depth,
      isActive: node.location.id == activeId,
      onSelect: () {
        ref.read(activeWorkspaceIdProvider.notifier).state = node.location.id;
        widget.onDismiss();
      },
      onRemove: () => _removeRepo(node.location.id),
    );
  }

  Widget _empty(AppPalette palette) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Text(
          'No repositories yet',
          style: TextStyle(
            color: palette.fg2,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      );

  Widget _newFolderField(AppPalette palette) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          controller: _newFolder,
          autofocus: true,
          style: TextStyle(color: palette.fg0, fontSize: 12.5),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Folder name',
            hintStyle: TextStyle(color: palette.fg3, fontSize: 12.5),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _confirmNewFolder(),
        ),
      );

  Widget _footer(AppPalette palette) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _action(palette, Icons.create_new_folder, 'New folder', () {
            setState(() => _addingFolder = !_addingFolder);
          }),
          _action(palette, Icons.folder_open, 'Open repository...', _openRepo),
          _action(
            palette,
            Icons.folder_copy,
            'Open folder of repos...',
            _openReposFolder,
          ),
          _action(palette, Icons.download, 'Clone repository...', _clone),
        ],
      );

  Widget _action(
    AppPalette palette,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 16, color: palette.fg1),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: palette.fg0, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmNewFolder() async {
    final name = _newFolder.text.trim();
    if (name.isEmpty) {
      setState(() => _addingFolder = false);
      return;
    }
    await ref.read(repoOrganizerProvider.notifier).createFolder(name);
    _newFolder.clear();
    if (mounted) setState(() => _addingFolder = false);
  }

  Future<void> _removeRepo(RepoId id) async {
    final active = ref.read(activeWorkspaceIdProvider);
    await ref.read(workspaceManagerProvider.notifier).remove(id);
    await ref.read(repoOrganizerProvider.notifier).refresh();
    if (active == id) {
      final remaining = ref.read(workspaceManagerProvider);
      ref.read(activeWorkspaceIdProvider.notifier).state =
          remaining.isEmpty ? null : remaining.first.location.id;
    }
  }

  Future<void> _openRepo() async {
    widget.onDismiss();
    final path = await ref.read(folderPickerProvider).pickFolder(
          'Open repository',
        );
    if (path == null) return;
    final ws = await ref.read(workspaceManagerProvider.notifier).open(path);
    await ref.read(repoOrganizerProvider.notifier).refresh();
    ref.read(activeWorkspaceIdProvider.notifier).state = ws.location.id;
  }

  Future<void> _openReposFolder() async {
    widget.onDismiss();
    final parent = await ref.read(folderPickerProvider).pickFolder(
          'Open folder of repositories',
        );
    if (parent == null) return;
    final paths =
        await ref.read(repoFolderScannerProvider).findRepositories(parent);
    if (!mounted) return;
    if (paths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No git repositories found in $parent')),
      );
      return;
    }
    final manager = ref.read(workspaceManagerProvider.notifier);
    RepoId? firstId;
    for (final path in paths) {
      try {
        final ws = await manager.open(path);
        firstId ??= ws.location.id;
      } on Object catch (_) {
        // Skip a repo that fails to open; keep opening the rest.
      }
    }
    await ref.read(repoOrganizerProvider.notifier).refresh();
    if (firstId != null) {
      ref.read(activeWorkspaceIdProvider.notifier).state = firstId;
    }
  }

  Future<void> _clone() async {
    widget.onDismiss();
    if (!mounted) return;
    await CloneDialog.show(context);
    await ref.read(repoOrganizerProvider.notifier).refresh();
  }
}
