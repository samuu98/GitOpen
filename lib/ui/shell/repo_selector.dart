import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/workspaces/workspace.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/ui/dialogs/clone_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Dropdown placed in the title bar that picks the active workspace.
/// Replaces the tab strip — the title bar gains drag area on either side.
class RepoSelector extends ConsumerStatefulWidget {
  const RepoSelector({super.key});

  @override
  ConsumerState<RepoSelector> createState() => _RepoSelectorState();
}

class _RepoSelectorState extends ConsumerState<RepoSelector> {
  final MenuController _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final workspaces = ref.watch(workspaceManagerProvider);
    final activeId = ref.watch(activeWorkspaceIdProvider);
    final active = workspaces
        .where((w) => w.location.id == activeId)
        .cast<Workspace?>()
        .firstWhere(
          (_) => true,
          orElse: () => null,
        );

    final palette = AppPalette.of(context);
    return MenuAnchor(
      controller: _menu,
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(palette.bg2),
        side: WidgetStateProperty.all(
          BorderSide(color: palette.border),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        padding: WidgetStateProperty.all(
          const EdgeInsets.symmetric(vertical: 4),
        ),
        elevation: WidgetStateProperty.all(8),
      ),
      menuChildren: [
        if (workspaces.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'No repositories open',
              style: TextStyle(
                color: palette.fg2,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          for (final w in workspaces)
            _RepoMenuItem(
              workspace: w,
              isActive: w.location.id == activeId,
              onSelect: () {
                ref.read(activeWorkspaceIdProvider.notifier).state =
                    w.location.id;
                _menu.close();
              },
              onClose: () => _close(w.location.id),
            ),
        Divider(height: 1, color: palette.border),
        MenuItemButton(
          style: ButtonStyle(
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) return palette.bg4;
              return Colors.transparent;
            }),
          ),
          leadingIcon: Icon(Icons.folder_open, size: 16, color: palette.fg1),
          onPressed: _openRepo,
          child: Text(
            'Open repository...',
            style: TextStyle(color: palette.fg0, fontSize: 12.5),
          ),
        ),
        MenuItemButton(
          style: ButtonStyle(
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) return palette.bg4;
              return Colors.transparent;
            }),
          ),
          leadingIcon: Icon(Icons.folder_copy, size: 16, color: palette.fg1),
          onPressed: _openReposFolder,
          child: Text(
            'Open folder of repos...',
            style: TextStyle(color: palette.fg0, fontSize: 12.5),
          ),
        ),
        MenuItemButton(
          style: ButtonStyle(
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) return palette.bg4;
              return Colors.transparent;
            }),
          ),
          leadingIcon: Icon(Icons.download, size: 16, color: palette.fg1),
          onPressed: _cloneRepo,
          child: Text(
            'Clone repository...',
            style: TextStyle(color: palette.fg0, fontSize: 12.5),
          ),
        ),
      ],
      builder: (context, controller, child) {
        return _SelectorButton(
          label: active?.location.displayName ?? 'No repository',
          isEmpty: active == null,
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
    );
  }

  Future<void> _openRepo() async {
    _menu.close();
    final picker = ref.read(folderPickerProvider);
    final path = await picker.pickFolder('Open repository');
    if (path == null) return;
    final manager = ref.read(workspaceManagerProvider.notifier);
    final ws = await manager.open(path);
    ref.read(activeWorkspaceIdProvider.notifier).state = ws.location.id;
  }

  Future<void> _openReposFolder() async {
    _menu.close();
    final picker = ref.read(folderPickerProvider);
    final parent = await picker.pickFolder('Open folder of repositories');
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
    if (firstId != null) {
      ref.read(activeWorkspaceIdProvider.notifier).state = firstId;
    }
  }

  Future<void> _cloneRepo() async {
    _menu.close();
    if (mounted) await CloneDialog.show(context);
  }

  Future<void> _close(RepoId id) async {
    final manager = ref.read(workspaceManagerProvider.notifier);
    await manager.close(id);
    final remaining = ref.read(workspaceManagerProvider);
    final active = ref.read(activeWorkspaceIdProvider);
    if (active == id) {
      ref.read(activeWorkspaceIdProvider.notifier).state =
          remaining.isNotEmpty ? remaining.first.location.id : null;
    }
  }
}

class _SelectorButton extends StatefulWidget {
  const _SelectorButton({
    required this.label,
    required this.isEmpty,
    required this.onTap,
  });
  final String label;
  final bool isEmpty;
  final VoidCallback onTap;

  @override
  State<_SelectorButton> createState() => _SelectorButtonState();
}

class _SelectorButtonState extends State<_SelectorButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 28,
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 420),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: _hover ? palette.bg4 : palette.bg2,
            border: Border.all(color: palette.borderStrong),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_outlined, size: 14, color: palette.fg1),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.isEmpty ? palette.fg2 : palette.fg0,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    fontStyle: widget.isEmpty
                        ? FontStyle.italic
                        : FontStyle.normal,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.expand_more, size: 16, color: palette.fg2),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepoMenuItem extends StatefulWidget {
  const _RepoMenuItem({
    required this.workspace,
    required this.isActive,
    required this.onSelect,
    required this.onClose,
  });
  final Workspace workspace;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  State<_RepoMenuItem> createState() => _RepoMenuItemState();
}

class _RepoMenuItemState extends State<_RepoMenuItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: _hover ? palette.bg4 : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 480),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                child: widget.isActive
                    ? Icon(Icons.check, size: 14, color: palette.accentCurrent)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.workspace.location.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.isActive ? palette.fg0 : palette.fg1,
                        fontSize: 12.5,
                        fontWeight: widget.isActive
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    Text(
                      widget.workspace.location.path,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.fg3,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    widget.onClose();
                  },
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _hover ? palette.bg5 : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Icon(Icons.close, size: 13, color: palette.fg2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
