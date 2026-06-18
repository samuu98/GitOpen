import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/common/divergence_badge.dart';
import 'package:gitopen/ui/shell/repo_tree_popover.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Title-bar button that opens the repository tree popover (the persistent
/// catalog of known repos, organized into folders).
class RepoSelector extends ConsumerStatefulWidget {
  const RepoSelector({super.key});

  @override
  ConsumerState<RepoSelector> createState() => _RepoSelectorState();
}

class _RepoSelectorState extends ConsumerState<RepoSelector> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _portal = OverlayPortalController();

  @override
  Widget build(BuildContext context) {
    final workspaces = ref.watch(workspaceManagerProvider);
    final activeId = ref.watch(activeWorkspaceIdProvider);
    final active =
        workspaces.firstWhereOrNull((w) => w.location.id == activeId);
    final status = active == null
        ? null
        : ref.watch(repoStatusProvider(active.location)).value;

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildOverlay,
        child: _SelectorButton(
          label: active?.location.displayName ?? 'No repository',
          isEmpty: active == null,
          ahead: status?.ahead ?? 0,
          behind: status?.behind ?? 0,
          onTap: _portal.toggle,
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return Stack(
      children: [
        // Full-screen barrier: a tap anywhere outside the popover dismisses it.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _portal.hide,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          offset: const Offset(0, 4),
          child: Align(
            alignment: Alignment.topLeft,
            child: RepoTreePopover(onDismiss: _portal.hide),
          ),
        ),
      ],
    );
  }
}

class _SelectorButton extends StatefulWidget {
  const _SelectorButton({
    required this.label,
    required this.isEmpty,
    required this.onTap,
    this.ahead = 0,
    this.behind = 0,
  });
  final String label;
  final bool isEmpty;
  final int ahead;
  final int behind;
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
                    fontStyle:
                        widget.isEmpty ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ),
              DivergenceBadge(ahead: widget.ahead, behind: widget.behind),
              const SizedBox(width: 6),
              Icon(Icons.expand_more, size: 16, color: palette.fg2),
            ],
          ),
        ),
      ),
    );
  }
}
