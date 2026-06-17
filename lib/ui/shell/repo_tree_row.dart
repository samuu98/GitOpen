import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Left padding for a row at [depth] in the tree.
double rowIndent(int depth) => 10 + depth * 16.0;

/// A collapsible folder header. Tapping it toggles its collapsed state.
class FolderRow extends ConsumerWidget {
  const FolderRow({required this.folder, required this.depth, super.key});
  final Folder folder;
  final int depth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: () => ref
          .read(repoOrganizerProvider.notifier)
          .setCollapsed(folder.id, collapsed: !folder.collapsed),
      child: Padding(
        padding: EdgeInsets.fromLTRB(rowIndent(depth), 6, 12, 6),
        child: Row(
          children: [
            Icon(
              folder.collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 16,
              color: palette.fg2,
            ),
            const SizedBox(width: 4),
            Icon(Icons.folder, size: 15, color: palette.fg1),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                folder.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.fg0,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.drag_indicator, size: 15, color: palette.fg3),
          ],
        ),
      ),
    );
  }
}

/// A repository row. Tapping selects it; the trailing menu removes it from
/// the catalog.
class RepoRow extends StatelessWidget {
  const RepoRow({
    required this.location,
    required this.depth,
    required this.isActive,
    required this.onSelect,
    required this.onRemove,
    super.key,
  });
  final RepoLocation location;
  final int depth;
  final bool isActive;
  final VoidCallback onSelect;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onSelect,
      child: Padding(
        padding: EdgeInsets.fromLTRB(rowIndent(depth), 5, 4, 5),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: isActive
                  ? Icon(Icons.check, size: 14, color: palette.accentCurrent)
                  : null,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    location.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isActive ? palette.fg0 : palette.fg1,
                      fontSize: 12.5,
                    ),
                  ),
                  Text(
                    location.path,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.fg3, fontSize: 11),
                  ),
                ],
              ),
            ),
            _RowMenu(onRemove: onRemove),
            Icon(Icons.drag_indicator, size: 15, color: palette.fg3),
          ],
        ),
      ),
    );
  }
}

class _RowMenu extends StatelessWidget {
  const _RowMenu({required this.onRemove});
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, size: 16, color: palette.fg2),
      tooltip: 'Repository actions',
      onSelected: (value) {
        if (value == 'remove') unawaited(onRemove());
      },
      itemBuilder: (_) => const [
        PopupMenuItem<String>(
          value: 'remove',
          child: Text('Remove from GitOpen'),
        ),
      ],
    );
  }
}
