import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/folder.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Left padding for a row at [depth] in the tree.
double rowIndent(int depth) => 10 + depth * 16.0;

/// A collapsible folder header. Tapping it toggles its collapsed state; the
/// trailing trash icon removes the folder (children move up to its parent).
class FolderRow extends ConsumerWidget {
  const FolderRow({
    required this.folder,
    required this.depth,
    required this.onRemove,
    super.key,
  });
  final Folder folder;
  final int depth;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: () => ref
          .read(repoOrganizerProvider.notifier)
          .setCollapsed(folder.id, collapsed: !folder.collapsed),
      child: Padding(
        padding: EdgeInsets.fromLTRB(rowIndent(depth), 6, 4, 6),
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
            _DeleteButton(onRemove: onRemove, tooltip: 'Remove folder'),
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
            _DeleteButton(onRemove: onRemove, tooltip: 'Remove from GitOpen'),
            Icon(Icons.drag_indicator, size: 15, color: palette.fg3),
          ],
        ),
      ),
    );
  }
}

/// A compact trash button used by both repo and folder rows. The actual
/// confirmation + removal lives in the popover handler [onRemove].
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onRemove, required this.tooltip});
  final Future<void> Function() onRemove;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return IconButton(
      icon: Icon(Icons.delete_outline, size: 16, color: palette.fg2),
      tooltip: tooltip,
      splashRadius: 16,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: () => unawaited(onRemove()),
    );
  }
}
