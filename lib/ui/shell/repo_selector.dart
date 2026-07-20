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
  const RepoSelector({super.key, this.compact = false});

  final bool compact;

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
    final active = workspaces.firstWhereOrNull(
      (w) => w.location.id == activeId,
    );
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
          compact: widget.compact,
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
    required this.compact,
    this.ahead = 0,
    this.behind = 0,
  });
  final String label;
  final bool isEmpty;
  final int ahead;
  final int behind;
  final VoidCallback onTap;
  final bool compact;

  @override
  State<_SelectorButton> createState() => _SelectorButtonState();
}

class _SelectorButtonState extends State<_SelectorButton> {
  bool _hover = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: widget.isEmpty ? 'Choose a repository' : widget.label,
      child: Semantics(
        button: true,
        label: widget.isEmpty
            ? 'Choose a repository'
            : 'Current repository: ${widget.label}',
        onTap: widget.onTap,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            excludeFromSemantics: true,
            onHover: (hovered) => setState(() => _hover = hovered),
            onFocusChange: (focused) => setState(() => _focused = focused),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: 28,
              constraints: BoxConstraints(
                minWidth: widget.compact ? 140 : 200,
                maxWidth: widget.compact ? 240 : 420,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _hover ? palette.bg4 : palette.bg2,
                border: Border.all(
                  color: _focused ? palette.accentRemote : palette.borderStrong,
                  width: _focused ? 1.5 : 1,
                ),
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
                  DivergenceBadge(ahead: widget.ahead, behind: widget.behind),
                  const SizedBox(width: 6),
                  Icon(Icons.expand_more, size: 16, color: palette.fg2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
