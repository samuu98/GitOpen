import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/workspaces/workspace.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/dialogs/push_branch_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/toolbar/branch_dropdown.dart';
import 'package:gitopen/ui/toolbar/open_dropdown.dart';
import 'package:gitopen/ui/toolbar/stash_dropdown.dart';
import 'package:gitopen/ui/toolbar/toolbar_buttons.dart';

/// Three-button toolbar for Fetch / Pull / Push, plus Branch, Stash and Open
/// dropdowns (each in its own file). Sync actions funnel through
/// [GitActionsController], which owns progress + auth-retry.
class GitToolbar extends ConsumerStatefulWidget {
  const GitToolbar({super.key, this.compact = false});

  final bool compact;

  @override
  ConsumerState<GitToolbar> createState() => _GitToolbarState();
}

class _GitToolbarState extends ConsumerState<GitToolbar> {
  /// Human-readable form of the configured shortcut for [action] (e.g.
  /// "F5"), or null when unbound — surfaced in tooltips so the bindings
  /// are discoverable outside the settings page.
  String? _shortcutLabel(String action) {
    final binding = ref.watch(appSettingsProvider).keybindings[action];
    if (binding == null) return null;
    return binding.keys
        .map((k) => k.keyLabel.isNotEmpty ? k.keyLabel : k.debugName ?? '?')
        .join(' + ');
  }

  String _tooltip(String base, String action) {
    final shortcut = _shortcutLabel(action);
    return shortcut == null ? base : '$base ($shortcut)';
  }

  @override
  Widget build(BuildContext context) {
    final activeId = ref.watch(activeWorkspaceIdProvider);
    final workspaces = ref.watch(workspaceManagerProvider);
    final active = workspaces
        .where((w) => w.location.id == activeId)
        .cast<Workspace?>()
        .firstOrNull;
    final enabled = active != null;
    final repo = active?.location;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ToolbarButton(
          icon: Icons.cloud_download_outlined,
          label: 'Fetch',
          enabled: enabled,
          tooltip: _tooltip('Fetch from origin', 'fetch'),
          compact: widget.compact,
          onTap: () => _fetch(repo!),
        ),
        ToolbarButton(
          icon: Icons.south,
          label: 'Pull',
          enabled: enabled,
          tooltip: _tooltip('Pull from origin', 'pull'),
          compact: widget.compact,
          onTap: () => unawaited(_pull(repo!)),
        ),
        _PushSplitButton(
          enabled: enabled,
          compact: widget.compact,
          tooltip: _tooltip('Push to origin', 'push'),
          onPush: () => unawaited(_push(repo!)),
          onMenu: (pos) => unawaited(_pushMenu(repo!, pos)),
        ),
        const SizedBox(width: 4),
        BranchDropdown(
          enabled: enabled,
          repo: repo,
          compact: widget.compact,
        ),
        const SizedBox(width: 2),
        StashDropdown(
          enabled: enabled,
          repo: repo,
          compact: widget.compact,
        ),
        const SizedBox(width: 2),
        OpenDropdown(
          enabled: enabled,
          repo: repo,
          compact: widget.compact,
        ),
      ],
    );
  }

  void _fetch(RepoLocation repo) =>
      unawaited(ref.read(gitActionsControllerProvider).fetch(context, repo));

  Future<void> _pull(RepoLocation repo) async {
    if (!await _confirm(
      'Pull from origin?',
      'This merges the latest changes from origin into the current branch.',
      'Pull',
    )) {
      return;
    }
    if (!mounted) return;
    await ref.read(gitActionsControllerProvider).pull(context, repo);
  }

  Future<void> _push(RepoLocation repo) async {
    if (!await _confirm(
      'Push to origin?',
      'This sends the current branch to origin.',
      'Push',
    )) {
      return;
    }
    if (!mounted) return;
    await ref.read(gitActionsControllerProvider).push(context, repo);
  }

  /// Returns whether the action may proceed: shows a confirmation dialog when
  /// the `confirmPushPull` setting is on, otherwise proceeds immediately.
  Future<bool> _confirm(String title, String body, String confirmLabel) async {
    if (!ref.read(appSettingsProvider).confirmPushPull) return true;
    return ConfirmDialog.show(
      context,
      title: title,
      body: body,
      confirmLabel: confirmLabel,
    );
  }

  Future<void> _pushMenu(RepoLocation repo, Offset pos) async {
    final selected = await AppContextMenu.show<String>(
      context,
      globalPosition: pos,
      entries: const [
        AppMenuItem(value: 'push', label: 'Push', icon: Icons.north),
        AppMenuItem(
          value: 'force',
          label: 'Force push (--force-with-lease)',
          icon: Icons.warning_amber_outlined,
          danger: true,
        ),
        AppMenuItem(
          value: 'tags',
          label: 'Push tags',
          icon: Icons.local_offer_outlined,
        ),
        AppMenuItem(
          value: 'branch',
          label: 'Push branch…',
          icon: Icons.alt_route,
        ),
      ],
    );
    if (selected == null || !mounted) return;

    final actions = ref.read(gitActionsControllerProvider);
    switch (selected) {
      case 'push':
        await actions.push(context, repo);
      case 'force':
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Force push?',
          body:
              'This rewrites the remote branch using --force-with-lease, '
              'and refuses if someone else pushed first.',
          confirmLabel: 'Force push',
          dangerous: true,
        );
        if (!confirmed || !mounted) return;
        await actions.push(context, repo, forceWithLease: true);
      case 'tags':
        await actions.push(context, repo, pushTags: true);
      case 'branch':
        final picked = await PushBranchDialog.show(context, ref, repo);
        if (picked == null || !mounted) return;
        await actions.push(
          context,
          repo,
          remote: picked.remote,
          branch: picked.branch,
        );
    }
  }
}

/// Push button + caret as one unit. The caret sits the same 3px after the
/// label as the other toolbar dropdowns ([ToolbarDropdownButton]), so every
/// toolbar caret is equidistant from its label. Tapping the label pushes;
/// tapping the caret opens the advanced push menu.
class _PushSplitButton extends StatelessWidget {
  const _PushSplitButton({
    required this.enabled,
    required this.compact,
    required this.tooltip,
    required this.onPush,
    required this.onMenu,
  });
  final bool enabled;
  final bool compact;
  final String tooltip;
  final VoidCallback onPush;
  final void Function(Offset globalPosition) onMenu;

  @override
  Widget build(BuildContext context) {
    final spacing = AppSpacing.of(context);
    final typography = AppTypography.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppInteractiveSurface(
          onTap: enabled ? onPush : null,
          tooltip: tooltip,
          semanticLabel: 'Push',
          height: spacing.regularControlHeight,
          alignment: null,
          padding: EdgeInsets.only(left: compact ? spacing.sm : spacing.md),
          child: (context, visual) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.north,
                size: spacing.regularIconSize,
                color: visual.foreground,
              ),
              if (!compact) ...[
                SizedBox(width: spacing.xs),
                Text(
                  'Push',
                  style: typography.body.copyWith(color: visual.foreground),
                ),
              ],
            ],
          ),
        ),
        AppInteractiveSurface(
          onTap: enabled ? () => onMenu(_menuPosition(context)) : null,
          tooltip: 'More push options',
          semanticLabel: 'More push options',
          height: spacing.regularControlHeight,
          alignment: null,
          padding: EdgeInsets.only(
            left: spacing.xxs,
            right: compact ? spacing.sm : spacing.md,
          ),
          child: (context, visual) => Icon(
            Icons.expand_more,
            size: spacing.compactIconSize,
            color: visual.foreground,
          ),
        ),
      ],
    );
  }

  Offset _menuPosition(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset(box.size.width, box.size.height));
  }
}
