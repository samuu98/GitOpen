import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git/auth_spec.dart';
import 'package:gitopen/application/launcher/repo_launcher.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/workspaces/workspace.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/auth_dialog.dart';
import 'package:gitopen/ui/dialogs/branch_create_dialog.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Three-button toolbar for Fetch / Pull / Push, plus Branch and Stash
/// dropdowns.
///
/// Converted to [ConsumerStatefulWidget] so it has a [BuildContext] for
/// showing [AuthDialog] when a sync operation fails with an auth error.
/// On success the dialog returns an [AuthSpec] which is used to re-run
/// the same operation once.
class GitToolbar extends ConsumerStatefulWidget {
  const GitToolbar({super.key});

  @override
  ConsumerState<GitToolbar> createState() => _GitToolbarState();
}

class _GitToolbarState extends ConsumerState<GitToolbar> {
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
        _ToolbarButton(
          icon: Icons.cloud_download_outlined,
          label: 'Fetch',
          enabled: enabled,
          onTap: () => _fetch(repo!),
        ),
        _ToolbarButton(
          icon: Icons.south,
          label: 'Pull',
          enabled: enabled,
          onTap: () => _pull(repo!),
        ),
        _ToolbarButton(
          icon: Icons.north,
          label: 'Push',
          enabled: enabled,
          onTap: () => _push(repo!),
        ),
        const SizedBox(width: 4),
        _BranchDropdown(enabled: enabled, repo: repo),
        const SizedBox(width: 2),
        _StashDropdown(enabled: enabled, repo: repo),
        const SizedBox(width: 2),
        _OpenDropdown(enabled: enabled, repo: repo),
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

// ---------------------------------------------------------------------------
// Branch dropdown
// ---------------------------------------------------------------------------

class _BranchDropdown extends ConsumerStatefulWidget {

  const _BranchDropdown({required this.enabled, required this.repo});
  final bool enabled;
  final RepoLocation? repo;

  @override
  ConsumerState<_BranchDropdown> createState() => _BranchDropdownState();
}

class _BranchDropdownState extends ConsumerState<_BranchDropdown> {
  final _menuController = MenuController();

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menuController,
      style: appMenuStyle(context),
      menuChildren: widget.enabled && widget.repo != null
          ? _buildBranchMenuItems(widget.repo!)
          : const [],
      child: _ToolbarDropdownButton(
        icon: Icons.account_tree_outlined,
        label: 'Branch',
        enabled: widget.enabled,
        onTap: () => _menuController.isOpen
            ? _menuController.close()
            : _menuController.open(),
      ),
    );
  }

  List<Widget> _buildBranchMenuItems(RepoLocation repo) {
    return [
      AppMenuButton(
        icon: Icons.add,
        label: 'New branch from HEAD',
        onPressed: () async {
          _menuController.close();
          if (!mounted) return;
          await BranchCreateDialog.show(context, repo);
        },
      ),
      AppMenuButton(
        icon: Icons.swap_horiz,
        label: 'Switch branch…',
        onPressed: () async {
          _menuController.close();
          if (!mounted) return;
          await _switchBranch(repo);
        },
      ),
      AppMenuButton(
        icon: Icons.drive_file_rename_outline,
        label: 'Rename current branch…',
        onPressed: () async {
          _menuController.close();
          if (!mounted) return;
          await _renameBranch(repo);
        },
      ),
      const AppMenuAnchorDivider(),
      AppMenuButton(
        icon: Icons.delete_outline,
        label: 'Delete branch…',
        danger: true,
        onPressed: () async {
          _menuController.close();
          if (!mounted) return;
          await _deleteBranch(repo);
        },
      ),
    ];
  }

  Future<void> _switchBranch(RepoLocation repo) async {
    final branches =
        await ref.read(gitReadOperationsProvider).getBranches(repo);
    final locals = branches.where((b) => !b.isRemote).toList();
    if (!mounted) return;
    final selected = await _showBranchPickerDialog(
      context,
      title: 'Switch branch',
      branches: locals.map((b) => b.name).toList(),
    );
    if (selected == null || !mounted) return;
    await ref.read(gitActionsControllerProvider).checkout(
          context,
          repo,
          selected,
        );
  }

  Future<void> _renameBranch(RepoLocation repo) async {
    final branches =
        await ref.read(gitReadOperationsProvider).getBranches(repo);
    final current = branches.where((b) => b.isCurrent).firstOrNull;
    if (current == null || !mounted) return;
    final newName = await _promptText(context, 'Rename current branch',
        label: 'New name', initial: current.name);
    if (newName == null || newName.trim().isEmpty || !mounted) return;
    await ref
        .read(gitActionsControllerProvider)
        .renameBranch(context, repo, current.name, newName.trim());
  }

  Future<void> _deleteBranch(RepoLocation repo) async {
    final branches =
        await ref.read(gitReadOperationsProvider).getBranches(repo);
    final locals = branches.where((b) => !b.isRemote).toList();
    if (!mounted) return;
    final selected = await _showBranchPickerDialog(
      context,
      title: 'Delete branch',
      branches: locals.map((b) => b.name).toList(),
    );
    if (selected == null || !mounted) return;
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete branch',
      body: 'Delete "$selected"? This cannot be undone.',
      confirmLabel: 'Delete',
      dangerous: true,
    );
    if (!confirmed || !mounted) return;
    await ref
        .read(gitActionsControllerProvider)
        .deleteBranch(context, repo, selected, force: true);
  }

  Future<String?> _showBranchPickerDialog(
    BuildContext context, {
    required String title,
    required List<String> branches,
  }) async {
    if (branches.isEmpty) return null;
    return showDialog<String>(
      context: context,
      builder: (ctx) => _BranchPickerDialog(title: title, branches: branches),
    );
  }

  Future<String?> _promptText(BuildContext context, String title,
          {required String label, String? initial}) =>
      _appPromptText(context, title, label: label, initial: initial);
}

// ---------------------------------------------------------------------------
// Stash dropdown
// ---------------------------------------------------------------------------

class _StashDropdown extends ConsumerStatefulWidget {

  const _StashDropdown({required this.enabled, required this.repo});
  final bool enabled;
  final RepoLocation? repo;

  @override
  ConsumerState<_StashDropdown> createState() => _StashDropdownState();
}

class _StashDropdownState extends ConsumerState<_StashDropdown> {
  final _menuController = MenuController();

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menuController,
      style: appMenuStyle(context),
      menuChildren: widget.enabled && widget.repo != null
          ? _buildStashMenuItems(widget.repo!)
          : const [],
      child: _ToolbarDropdownButton(
        icon: Icons.inventory_2_outlined,
        label: 'Stash',
        enabled: widget.enabled,
        onTap: () => _menuController.isOpen
            ? _menuController.close()
            : _menuController.open(),
      ),
    );
  }

  List<Widget> _buildStashMenuItems(RepoLocation repo) {
    return [
      AppMenuButton(
        icon: Icons.save_outlined,
        label: 'Stash changes…',
        onPressed: () async {
          _menuController.close();
          if (!context.mounted) return;
          await _stashSave(repo);
        },
      ),
      AppMenuButton(
        icon: Icons.arrow_downward,
        label: 'Apply latest',
        onPressed: () async {
          _menuController.close();
          await ref.read(gitActionsControllerProvider).stashApply(
                context,
                repo,
                0,
              );
        },
      ),
      AppMenuButton(
        icon: Icons.eject_outlined,
        label: 'Pop latest',
        onPressed: () async {
          _menuController.close();
          await ref.read(gitActionsControllerProvider).stashPop(
                context,
                repo,
                0,
              );
        },
      ),
      const AppMenuAnchorDivider(),
      AppMenuButton(
        icon: Icons.list_outlined,
        label: 'View stashes…',
        onPressed: () async {
          _menuController.close();
          if (!context.mounted) return;
          await _viewStashes(repo);
        },
      ),
    ];
  }

  Future<void> _stashSave(RepoLocation repo) async {
    final msg = await _appPromptText(context, 'Stash changes',
        label: 'Message (optional)');
    if (!mounted) return;
    await ref
        .read(gitActionsControllerProvider)
        .stashSave(context, repo, msg?.trim() ?? '');
  }

  Future<void> _viewStashes(RepoLocation repo) async {
    final stashes = await ref.read(gitReadOperationsProvider).getStashes(repo);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return AppDialog(
          title: 'Stashes',
          width: 420,
          content: stashes.isEmpty
              ? Text('No stashes.',
                  style: TextStyle(color: palette.fg2, fontSize: 12.5))
              : SizedBox(
                  height: 280,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: stashes.length,
                    itemBuilder: (_, i) {
                      final s = stashes[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'stash@{${s.index}}',
                              style: TextStyle(
                                color: palette.fg0,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Text(
                              s.message,
                              style: TextStyle(
                                  color: palette.fg2, fontSize: 11.5),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
          actions: [
            AppButton.secondary(
              label: 'Close',
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        );
      },
    );
  }
}

/// Single-line text prompt shared between the toolbar dropdowns.
Future<String?> _appPromptText(BuildContext context, String title,
    {required String label, String? initial}) async {
  final ctl = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final palette = AppPalette.of(ctx);
      return AppDialog(
        title: title,
        width: 420,
        content: TextField(
          controller: ctl,
          autofocus: true,
          style: TextStyle(color: palette.fg0, fontSize: 13),
          decoration: appInputDecoration(ctx, label: label),
          onSubmitted: (_) => Navigator.pop(ctx, ctl.text),
        ),
        actions: [
          AppButton.secondary(
              label: 'Cancel', onPressed: () => Navigator.pop(ctx)),
          AppButton.primary(
              label: 'OK', onPressed: () => Navigator.pop(ctx, ctl.text)),
        ],
      );
    },
  );
  ctl.dispose();
  return result;
}

// ---------------------------------------------------------------------------
// Open dropdown — reveal in files / terminal / editor
// ---------------------------------------------------------------------------

class _OpenDropdown extends ConsumerStatefulWidget {
  const _OpenDropdown({required this.enabled, required this.repo});
  final bool enabled;
  final RepoLocation? repo;

  @override
  ConsumerState<_OpenDropdown> createState() => _OpenDropdownState();
}

class _OpenDropdownState extends ConsumerState<_OpenDropdown> {
  final _menuController = MenuController();

  @override
  Widget build(BuildContext context) {
    final editorsAsync = ref.watch(availableEditorsProvider);
    return MenuAnchor(
      controller: _menuController,
      style: appMenuStyle(context),
      menuChildren: widget.enabled && widget.repo != null
          ? _buildMenuItems(widget.repo!, editorsAsync.valueOrNull ?? const [])
          : const [],
      child: _ToolbarDropdownButton(
        icon: Icons.open_in_new,
        label: 'Open',
        enabled: widget.enabled,
        onTap: () => _menuController.isOpen
            ? _menuController.close()
            : _menuController.open(),
      ),
    );
  }

  List<Widget> _buildMenuItems(RepoLocation repo, List<EditorTarget> editors) {
    final items = <Widget>[
      AppMenuButton(
        icon: Icons.folder_open,
        label: 'Show in file explorer',
        onPressed: () {
          _menuController.close();
          unawaited(
            _run(() => ref.read(repoLauncherProvider).revealInFiles(repo)),
          );
        },
      ),
      AppMenuButton(
        icon: Icons.terminal,
        label: 'Open in terminal',
        onPressed: () {
          _menuController.close();
          unawaited(
            _run(() => ref.read(repoLauncherProvider).openInTerminal(repo)),
          );
        },
      ),
      const AppMenuAnchorDivider(),
    ];

    if (editors.isEmpty) {
      items.add(AppMenuButton(
        icon: Icons.code,
        label: 'Open in VS Code',
        onPressed: () {
          _menuController.close();
          unawaited(
            _run(
              () => ref.read(repoLauncherProvider).openInEditor(
                    repo,
                    const EditorTarget(
                      id: 'vscode',
                      displayName: 'VS Code',
                      executable: 'code',
                    ),
                  ),
            ),
          );
        },
      ));
    } else {
      for (final editor in editors) {
        items.add(AppMenuButton(
          icon: Icons.code,
          label: 'Open in ${editor.displayName}',
          onPressed: () {
            _menuController.close();
            unawaited(
              _run(
                () =>
                    ref.read(repoLauncherProvider).openInEditor(repo, editor),
              ),
            );
          },
        ));
      }
    }
    return items;
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on LauncherException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Branch picker dialog
// ---------------------------------------------------------------------------

class _BranchPickerDialog extends StatefulWidget {
  const _BranchPickerDialog({required this.title, required this.branches});
  final String title;
  final List<String> branches;

  @override
  State<_BranchPickerDialog> createState() => _BranchPickerDialogState();
}

class _BranchPickerDialogState extends State<_BranchPickerDialog> {
  String? _selected;
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final filtered = widget.branches
        .where((b) => b.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
    return AppDialog(
      title: widget.title,
      width: 380,
      content: SizedBox(
        height: 320,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              style: TextStyle(color: palette.fg0, fontSize: 13),
              decoration: appInputDecoration(context, label: 'Filter…')
                  .copyWith(
                prefixIcon:
                    Icon(Icons.search, size: 16, color: palette.fg2),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final b = filtered[i];
                  final selected = _selected == b;
                  return InkWell(
                    onTap: () => setState(() => _selected = b),
                    child: Container(
                      color:
                          selected ? palette.bgAccent : Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Text(
                        b,
                        style: TextStyle(
                          fontSize: 13,
                          color: selected ? palette.fg0 : palette.fg1,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        AppButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        AppButton.primary(
          label: 'OK',
          onPressed: _selected != null
              ? () => Navigator.pop(context, _selected)
              : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared toolbar widgets
// ---------------------------------------------------------------------------

class _ToolbarButton extends StatelessWidget {

  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: palette.fg1),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: palette.fg0,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dropdown trigger button — same visual style as [_ToolbarButton] but includes
/// a small chevron to signal it opens a menu.
class _ToolbarDropdownButton extends StatelessWidget {

  const _ToolbarDropdownButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: palette.fg1),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: palette.fg0,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 3),
              Icon(Icons.expand_more, size: 12, color: palette.fg2),
            ],
          ),
        ),
      ),
    );
  }
}
