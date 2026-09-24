import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/workspaces/repo_tree_node.dart';
import 'package:gitopen/domain/repositories/folder_id.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/clone_dialog.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/shell/repo_tree_drag.dart';
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
                      itemBuilder: (context, i) =>
                          _draggableRow(rows[i], activeId),
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
      return FolderRow(
        folder: node.folder,
        depth: row.depth,
        onRemove: () => _removeFolder(node.folder.id, node.folder.name),
      );
    }
    node as RepoNode;
    return RepoRow(
      location: node.location,
      depth: row.depth,
      isActive: node.location.id == activeId,
      onSelect: () => _selectRepo(node.location),
      onRemove: () => _removeRepo(node.location.id, node.location.displayName),
    );
  }

  void _selectRepo(RepoLocation location) {
    final manager = ref.read(workspaceManagerProvider.notifier);
    final activeNotifier = ref.read(activeWorkspaceIdProvider.notifier);
    final ops = ref.read(operationsProvider.notifier);
    widget.onDismiss();
    final opId = ops.start(OpKind.other, 'Open repository');
    unawaited(() async {
      try {
        final workspace = await manager.open(location.path);
        activeNotifier.state = workspace.location.id;
        ops.finishSuccess(opId);
      } on Object catch (error) {
        ops.finishFailure(opId, '$error');
      }
    }());
  }

  Widget _draggableRow(VisibleRow row, RepoId? activeId) {
    final node = row.node;
    final DragRef data;
    final String label;
    if (node is FolderNode) {
      data = FolderDragRef(node.folder.id);
      label = node.folder.name;
    } else {
      node as RepoNode;
      data = RepoDragRef(node.location.id);
      label = node.location.displayName;
    }
    return DragTreeRow(
      dragData: data,
      label: label,
      isFolder: node is FolderNode,
      canAccept: (dragged) => !_sameNode(dragged, row),
      onDrop: (dragged, zone) => _handleDrop(dragged, row, zone),
      child: _rowFor(row, activeId),
    );
  }

  void _handleDrop(DragRef dragged, VisibleRow target, DropZone zone) {
    final rows = flattenVisible(ref.read(repoOrganizerProvider));
    final targetNode = target.node;
    final FolderId? destParent;
    final int atIndex;
    if (zone == DropZone.into && targetNode is FolderNode) {
      destParent = targetNode.folder.id;
      atIndex = 1 << 20; // append; the store clamps to the child count
    } else {
      destParent = target.parentId;
      final raw = resolveDropIndex(
        hoveredIndex: target.indexInParent,
        isTopHalf: zone == DropZone.before,
      );
      final moved = _findRow(rows, dragged);
      atIndex = (moved != null && moved.parentId == destParent)
          ? adjustForSameParent(rawIndex: raw, movedIndex: moved.indexInParent)
          : raw;
    }
    final organizer = ref.read(repoOrganizerProvider.notifier);
    switch (dragged) {
      case RepoDragRef(:final id):
        unawaited(
          organizer.moveRepo(id, atIndex: atIndex, toParent: destParent),
        );
      case FolderDragRef(:final id):
        unawaited(
          organizer.moveFolder(id, atIndex: atIndex, toParent: destParent),
        );
    }
  }

  VisibleRow? _findRow(List<VisibleRow> rows, DragRef dragged) {
    for (final r in rows) {
      if (_sameNode(dragged, r)) return r;
    }
    return null;
  }

  bool _sameNode(DragRef dragged, VisibleRow row) {
    final n = row.node;
    return (dragged is RepoDragRef &&
            n is RepoNode &&
            n.location.id == dragged.id) ||
        (dragged is FolderDragRef &&
            n is FolderNode &&
            n.folder.id == dragged.id);
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
      _action(palette, Icons.folder_open, 'Open repository…', _openRepo),
      _action(
        palette,
        Icons.folder_copy,
        'Open folder of repos…',
        _openReposFolder,
      ),
      _action(palette, Icons.download, 'Clone repository…', _clone),
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

  Future<void> _removeRepo(RepoId id, String name) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Remove repository?',
      body:
          "'$name' will be removed from GitOpen's list. Your files on disk "
          'are not touched.',
      confirmLabel: 'Remove',
      dangerous: true,
    );
    if (!ok || !mounted) return;
    final active = ref.read(activeWorkspaceIdProvider);
    await ref.read(workspaceManagerProvider.notifier).remove(id);
    await ref.read(repoOrganizerProvider.notifier).refresh();
    if (active == id) {
      final remaining = ref.read(workspaceManagerProvider);
      ref.read(activeWorkspaceIdProvider.notifier).state = remaining.isEmpty
          ? null
          : remaining.first.location.id;
    }
  }

  Future<void> _removeFolder(FolderId id, String name) async {
    final ok = await ConfirmDialog.show(
      context,
      title: 'Remove folder?',
      body:
          "The folder '$name' will be removed. Repositories and folders "
          'inside it move up to the level above; nothing is deleted from '
          'disk.',
      confirmLabel: 'Remove',
      dangerous: true,
    );
    if (!ok || !mounted) return;
    await ref.read(repoOrganizerProvider.notifier).removeFolder(id);
  }

  // NOTE: these flows call `widget.onDismiss()`, which hides the OverlayPortal
  // and DISPOSES this popover. So every provider/notifier must be read BEFORE
  // the dismiss; using `ref` (or `context`) after the async gap would hit a
  // disposed widget and throw — and with no try/catch that error is swallowed,
  // silently doing nothing (the repo never gets added).

  Future<void> _openRepo() async {
    final picker = ref.read(folderPickerProvider);
    final manager = ref.read(workspaceManagerProvider.notifier);
    final organizer = ref.read(repoOrganizerProvider.notifier);
    final activeNotifier = ref.read(activeWorkspaceIdProvider.notifier);
    final ops = ref.read(operationsProvider.notifier);
    widget.onDismiss();
    final path = await picker.pickFolder('Open repository');
    if (path == null) return;
    final opId = ops.start(OpKind.other, 'Open repository');
    try {
      final ws = await manager.open(path);
      await organizer.refresh();
      activeNotifier.state = ws.location.id;
      ops.finishSuccess(opId);
    } on Object catch (error) {
      ops.finishFailure(opId, '$error');
    }
  }

  Future<void> _openReposFolder() async {
    final picker = ref.read(folderPickerProvider);
    final scanner = ref.read(repoFolderScannerProvider);
    final manager = ref.read(workspaceManagerProvider.notifier);
    final organizer = ref.read(repoOrganizerProvider.notifier);
    final activeNotifier = ref.read(activeWorkspaceIdProvider.notifier);
    // The messenger is an ancestor State that outlives this popover, so it is
    // safe to use after the dismiss below.
    final messenger = ScaffoldMessenger.of(context);
    widget.onDismiss();
    final parent = await picker.pickFolder('Open folder of repositories');
    if (parent == null) return;
    final paths = await scanner.findRepositories(parent);
    if (paths.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text('No git repositories found in $parent')),
      );
      return;
    }
    RepoId? firstId;
    for (final path in paths) {
      try {
        final ws = await manager.open(path);
        firstId ??= ws.location.id;
      } on Object catch (_) {
        // Skip a repo that fails to open; keep opening the rest.
      }
    }
    await organizer.refresh();
    if (firstId != null) activeNotifier.state = firstId;
  }

  Future<void> _clone() async {
    // Read before showing the dialog; dismiss only after it closes so the
    // dialog's context (this popover) is still valid when it opens.
    final organizer = ref.read(repoOrganizerProvider.notifier);
    final dismiss = widget.onDismiss;
    await CloneDialog.show(context);
    dismiss();
    await organizer.refresh();
  }
}

/// A tree row that can be dragged and is itself a drop target. Reports the
/// drop [DropZone] (computed from the pointer's vertical position) to
/// [onDrop]; draws an insertion line / into-folder highlight while hovered.
class DragTreeRow extends StatefulWidget {
  const DragTreeRow({
    required this.dragData,
    required this.label,
    required this.isFolder,
    required this.canAccept,
    required this.onDrop,
    required this.child,
    super.key,
  });
  final DragRef dragData;
  final String label;
  final bool isFolder;
  final bool Function(DragRef dragged) canAccept;
  final void Function(DragRef dragged, DropZone zone) onDrop;
  final Widget child;

  @override
  State<DragTreeRow> createState() => _DragTreeRowState();
}

class _DragTreeRowState extends State<DragTreeRow> {
  DropZone? _zone;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Draggable<DragRef>(
      data: widget.dragData,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _feedback(palette),
      childWhenDragging: Opacity(opacity: 0.4, child: widget.child),
      child: DragTarget<DragRef>(
        onWillAcceptWithDetails: (d) => widget.canAccept(d.data),
        onMove: (d) => _updateZone(d.offset),
        onLeave: (_) => _clearZone(),
        onAcceptWithDetails: (d) {
          final zone = _zone ?? DropZone.after;
          _clearZone();
          widget.onDrop(d.data, zone);
        },
        builder: (context, candidate, rejected) =>
            _decorated(palette, active: candidate.isNotEmpty),
      ),
    );
  }

  void _updateZone(Offset globalPointer) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(globalPointer);
    final frac = (local.dy / box.size.height).clamp(0.0, 1.0);
    final z = zoneFor(fraction: frac, isFolder: widget.isFolder);
    if (z != _zone) setState(() => _zone = z);
  }

  void _clearZone() {
    if (_zone != null) setState(() => _zone = null);
  }

  Widget _decorated(AppPalette palette, {required bool active}) {
    final zone = active ? _zone : null;
    final line = BorderSide(color: palette.accentCurrent, width: 2);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: zone == DropZone.into
            ? palette.accentCurrent.withValues(alpha: 0.15)
            : null,
        border: Border(
          top: zone == DropZone.before ? line : BorderSide.none,
          bottom: zone == DropZone.after ? line : BorderSide.none,
        ),
      ),
      child: widget.child,
    );
  }

  Widget _feedback(AppPalette palette) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: palette.bg4,
          border: Border.all(color: palette.borderStrong),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.isFolder ? Icons.folder : Icons.folder_outlined,
              size: 14,
              color: palette.fg1,
            ),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: TextStyle(color: palette.fg0, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
