import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/workspaces/workspace.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
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
}
