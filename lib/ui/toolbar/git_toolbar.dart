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
          onTap: () => _pull(repo!),
        ),
        ToolbarButton(
          icon: Icons.north,
          label: 'Push',
          enabled: enabled,
          tooltip: 'Push to origin',
          onTap: () => _push(repo!),
        ),
        _PushMenuCaret(
          enabled: enabled,
          onOpen: (pos) => unawaited(_pushMenu(repo!, pos)),
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

  void _pull(RepoLocation repo) =>
      unawaited(ref.read(gitActionsControllerProvider).pull(context, repo));

  void _push(RepoLocation repo) =>
      unawaited(ref.read(gitActionsControllerProvider).push(context, repo));

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

/// Narrow caret that opens advanced push actions while keeping the default
/// Push button unchanged.
class _PushMenuCaret extends StatelessWidget {
  const _PushMenuCaret({
    required this.enabled,
    required this.onOpen,
  });
  final bool enabled;
  final void Function(Offset globalPosition) onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: InkWell(
        onTapDown: enabled ? (d) => onOpen(d.globalPosition) : null,
        onTap: enabled ? () {} : null,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Icon(Icons.expand_more, size: 12, color: palette.fg2),
        ),
      ),
    );
  }
}
