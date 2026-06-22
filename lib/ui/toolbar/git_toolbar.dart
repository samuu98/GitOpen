import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/workspaces/workspace.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/dialogs/push_branch_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/toolbar/branch_dropdown.dart';
import 'package:gitopen/ui/toolbar/open_dropdown.dart';
import 'package:gitopen/ui/toolbar/stash_dropdown.dart';
import 'package:gitopen/ui/toolbar/toolbar_buttons.dart';

/// Three-button toolbar for Fetch / Pull / Push, plus Branch, Stash and Open
/// dropdowns (each in its own file). Sync actions funnel through
/// [GitActionsController], which owns progress + auth-retry.
class GitToolbar extends ConsumerStatefulWidget {
  const GitToolbar({super.key});

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
          onTap: () => _fetch(repo!),
        ),
        ToolbarButton(
          icon: Icons.south,
          label: 'Pull',
          enabled: enabled,
          tooltip: 'Pull from origin',
          onTap: () => unawaited(_pull(repo!)),
        ),
        _PushSplitButton(
          enabled: enabled,
          onPush: () => unawaited(_push(repo!)),
          onMenu: (pos) => unawaited(_pushMenu(repo!, pos)),
        ),
        const SizedBox(width: 4),
        BranchDropdown(enabled: enabled, repo: repo),
        const SizedBox(width: 2),
        StashDropdown(enabled: enabled, repo: repo),
        const SizedBox(width: 2),
        OpenDropdown(enabled: enabled, repo: repo),
      ],
    );
  }

  void _fetch(RepoLocation repo) =>
      unawaited(ref.read(gitActionsControllerProvider).fetch(context, repo));

  Future<void> _pull(RepoLocation repo) async {
    if (!await _confirm(
      'Pull',
      'Pull from origin into the current branch?',
      'Pull',
    )) {
      return;
    }
    if (!mounted) return;
    await ref.read(gitActionsControllerProvider).pull(context, repo);
  }

  Future<void> _push(RepoLocation repo) async {
    if (!await _confirm(
      'Push',
      'Push the current branch to origin?',
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
          label: 'Push branch...',
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
          title: 'Force push',
          body: 'Force-push with --force-with-lease? This rewrites the '
              'remote branch, but refuses if someone else pushed first.',
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
    required this.onPush,
    required this.onMenu,
  });
  final bool enabled;
  final VoidCallback onPush;
  final void Function(Offset globalPosition) onMenu;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final spacing = AppSpacing.of(context);
    final radii = AppRadii.of(context);
    final typography = AppTypography.of(context);
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Push to origin',
            waitDuration: const Duration(milliseconds: 500),
            child: InkWell(
              onTap: enabled ? onPush : null,
              borderRadius: radii.controlRadius,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  spacing.md - 2,
                  spacing.xs,
                  0,
                  spacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.north, size: 14, color: palette.fg1),
                    const SizedBox(width: 5),
                    Text(
                      'Push',
                      style: typography.body.copyWith(color: palette.fg0),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 3px gap before the caret — identical to ToolbarDropdownButton.
          Tooltip(
            message: 'More push options',
            waitDuration: const Duration(milliseconds: 500),
            child: InkWell(
              onTapDown: enabled ? (d) => onMenu(d.globalPosition) : null,
              onTap: enabled ? () {} : null,
              borderRadius: radii.controlRadius,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  3,
                  spacing.xs,
                  spacing.md - 2,
                  spacing.xs,
                ),
                child: Icon(Icons.expand_more, size: 12, color: palette.fg2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
