import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/providers.dart';
import '../../application/workspaces/workspace.dart';
import '../../domain/repositories/repo_id.dart';
import '../dialogs/clone_dialog.dart';

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
    final active =
        workspaces.where((w) => w.location.id == activeId).cast<Workspace?>().firstWhere(
              (_) => true,
              orElse: () => null,
            );

    return MenuAnchor(
      controller: _menu,
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(const Color(0xFF25252A)),
        side: WidgetStateProperty.all(
          const BorderSide(color: Color(0xFF313137)),
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
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'No repositories open',
              style: TextStyle(color: Color(0xFF888892), fontSize: 12, fontStyle: FontStyle.italic),
            ),
          )
        else
          for (final w in workspaces)
            _RepoMenuItem(
              workspace: w,
              isActive: w.location.id == activeId,
              onSelect: () {
                ref.read(activeWorkspaceIdProvider.notifier).state = w.location.id;
                _menu.close();
              },
              onClose: () => _close(w.location.id),
            ),
        const Divider(height: 1, color: Color(0xFF313137)),
        MenuItemButton(
          style: ButtonStyle(
            padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) return const Color(0xFF34343A);
              return Colors.transparent;
            }),
          ),
          leadingIcon: const Icon(Icons.folder_open, size: 16, color: Color(0xFFB8B8BC)),
          onPressed: _openRepo,
          child: const Text(
            'Open repository...',
            style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 12.5),
          ),
        ),
        MenuItemButton(
          style: ButtonStyle(
            padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) return const Color(0xFF34343A);
              return Colors.transparent;
            }),
          ),
          leadingIcon: const Icon(Icons.download, size: 16, color: Color(0xFFB8B8BC)),
          onPressed: _cloneRepo,
          child: const Text(
            'Clone repository...',
            style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 12.5),
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
  final String label;
  final bool isEmpty;
  final VoidCallback onTap;
  const _SelectorButton({
    required this.label,
    required this.isEmpty,
    required this.onTap,
  });

  @override
  State<_SelectorButton> createState() => _SelectorButtonState();
}

class _SelectorButtonState extends State<_SelectorButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
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
            color: _hover ? const Color(0xFF34343A) : const Color(0xFF25252A),
            border: Border.all(color: const Color(0xFF404048)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_outlined, size: 14, color: Color(0xFFB8B8BC)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.isEmpty ? const Color(0xFF888892) : const Color(0xFFD4D4D4),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    fontStyle: widget.isEmpty ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.expand_more, size: 16, color: Color(0xFF888892)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepoMenuItem extends StatefulWidget {
  final Workspace workspace;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  const _RepoMenuItem({
    required this.workspace,
    required this.isActive,
    required this.onSelect,
    required this.onClose,
  });

  @override
  State<_RepoMenuItem> createState() => _RepoMenuItemState();
}

class _RepoMenuItemState extends State<_RepoMenuItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onSelect,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: _hover ? const Color(0xFF34343A) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 480),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                child: widget.isActive
                    ? const Icon(Icons.check, size: 14, color: Color(0xFF4EC9B0))
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
                        color: widget.isActive ? const Color(0xFFD4D4D4) : const Color(0xFFB8B8BC),
                        fontSize: 12.5,
                        fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    Text(
                      widget.workspace.location.path,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF5D5D65),
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
                      color: _hover ? const Color(0xFF3D3D44) : Colors.transparent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Icon(Icons.close, size: 13, color: Color(0xFF888892)),
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
