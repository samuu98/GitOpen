import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/active_workspace_provider.dart';
import '../../application/auth/auth_profile.dart';
import '../../application/git/auth_spec.dart';
import '../../application/git/git_progress.dart';
import '../../application/git/git_write_operations.dart';
import '../../application/launcher/repo_launcher.dart';
import '../../application/operations/running_operation.dart';
import '../../application/providers.dart';
import '../../application/repo_revision.dart';
import '../../application/settings/app_settings.dart';
import '../../domain/repositories/repo_location.dart';
import '../../infrastructure/git/git_process_runner.dart';
import '../common/app_context_menu.dart';
import '../dialogs/account_switcher_dialog.dart';
import '../dialogs/app_dialog.dart';
import '../dialogs/auth_dialog.dart';
import '../dialogs/branch_create_dialog.dart';
import '../dialogs/confirm_dialog.dart';
import '../theme/app_palette.dart';

/// Three-button toolbar for Fetch / Pull / Push, plus Branch and Stash dropdowns.
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
    final active =
        workspaces.where((w) => w.location.id == activeId).cast<dynamic>().firstOrNull;
    final enabled = active != null;
    final repo = enabled ? active!.location as RepoLocation : null;

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

  Future<void> _fetch(RepoLocation repo) => _runStream(
        OpKind.fetch,
        'Fetching origin',
        repo,
        (auth) => ref.read(gitWriteOperationsProvider).fetch(repo, auth: auth),
      );

  Future<void> _pull(RepoLocation repo) {
    final strategy = switch (ref.read(appSettingsProvider).defaultPullStrategy) {
      DefaultPullStrategy.ffOnly => PullStrategy.ffOnly,
      DefaultPullStrategy.merge => PullStrategy.merge,
      DefaultPullStrategy.rebase => PullStrategy.rebase,
    };
    return _runStream(
      OpKind.pull,
      'Pulling',
      repo,
      (auth) => ref.read(gitWriteOperationsProvider).pull(repo, strategy, auth: auth),
    );
  }

  Future<void> _push(RepoLocation repo) => _runStream(
        OpKind.push,
        'Pushing',
        repo,
        (auth) => ref.read(gitWriteOperationsProvider).push(repo, auth: auth),
      );

  /// Runs a streaming git operation, tracking it in [operationsProvider].
  ///
  /// On an auth-style failure (bad credential) or wrong-account failure
  /// (HTTP 404 "repository not found" — typical when two GitHub accounts
  /// share the same host and the wrong one is being used) the user is
  /// prompted with [AccountSwitcherDialog].  The chosen profile is bound
  /// to this repo so subsequent operations pick it up automatically; the
  /// operation is then retried once.
  Future<void> _runStream(
    OpKind kind,
    String label,
    RepoLocation repo,
    Stream<GitProgress> Function(AuthSpec? auth) streamFactory, {
    AuthProfile? profile,
  }) async {
    final ops = ref.read(operationsProvider.notifier);
    final id = ops.start(kind, label, repo: repo);
    profile ??= await ref.read(authResolverProvider).resolveForRepo(repo);
    try {
      await for (final ev in streamFactory(profile?.spec)) {
        ops.updateProgress(id, ev.fraction, ev.phase);
      }
      ops.finishSuccess(id);
      refreshRepo(ref, repo);
    } catch (e) {
      // Inspect ONLY the git stderr — never `e.toString()`, which embeds the
      // git argv. With the credential helper active those args contain the
      // literal word `Authorization` (from `http.extraheader=Authorization:`),
      // which would otherwise falsely match the auth-error heuristic.
      final stderr = e is GitProcessException ? e.stderr : e.toString();
      final auth = _isAuthError(stderr);
      final wrongAccount = !auth && _isWrongAccountError(stderr);
      if (auth || wrongAccount) {
        ops.finishFailure(
          id,
          wrongAccount
              ? 'Repository not visible to current account'
              : 'Authentication required',
        );
        await _promptAccountAndRetry(
          kind,
          label,
          repo,
          streamFactory,
          currentProfile: profile,
          contextMessage: wrongAccount
              ? 'Git returned "repository not found" — '
                  'the active account likely cannot see this repo.'
              : 'The active credential was rejected.',
        );
      } else {
        ops.finishFailure(id, e.toString());
      }
    }
  }

  /// Detects auth-failure signals from git stderr.  Patterns are scoped to
  /// phrases git actually emits — avoid loose substrings like `'auth'`.
  bool _isAuthError(String stderr) {
    final lower = stderr.toLowerCase();
    return lower.contains('authentication failed') ||
        lower.contains('invalid username or password') ||
        lower.contains('could not read username') ||
        lower.contains('could not read password') ||
        lower.contains('terminal prompts disabled') ||
        lower.contains('http basic: access denied') ||
        lower.contains('remote: invalid credentials') ||
        lower.contains('remote: denied') ||
        lower.contains('permission denied') ||
        lower.contains('error: 401') ||
        lower.contains('error: 403');
  }

  /// "Repository not found" is GitHub's response when the authenticated user
  /// lacks access to a private repo — common when multiple accounts share
  /// the host and the wrong one is being used.
  bool _isWrongAccountError(String stderr) {
    final lower = stderr.toLowerCase();
    return lower.contains('repository not found') ||
        lower.contains('remote: not found') ||
        lower.contains('error: 404');
  }

  /// Shows [AccountSwitcherDialog]; on selection binds the chosen profile to
  /// this repo and re-runs the operation once with the new credential.
  Future<void> _promptAccountAndRetry(
    OpKind kind,
    String label,
    RepoLocation repo,
    Stream<GitProgress> Function(AuthSpec? auth) streamFactory, {
    required AuthProfile? currentProfile,
    required String contextMessage,
  }) async {
    if (!mounted) return;
    final host = await ref.read(authResolverProvider).hostFromRepo(repo, 'origin')
        ?? 'github.com';
    if (!mounted) return;
    final chosen = await AccountSwitcherDialog.show(
      context,
      host: host,
      contextMessage: contextMessage,
      currentProfileId: currentProfile?.id,
    );
    if (chosen == null) return;
    await ref
        .read(appSettingsProvider.notifier)
        .setAuthBinding(repo.id.value, chosen.id);
    await _runStream(kind, label, repo, streamFactory, profile: chosen);
  }
}

// ---------------------------------------------------------------------------
// Branch dropdown
// ---------------------------------------------------------------------------

class _BranchDropdown extends ConsumerStatefulWidget {
  final bool enabled;
  final RepoLocation? repo;

  const _BranchDropdown({required this.enabled, required this.repo});

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
          refreshRepo(ref, repo);
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
    final branches = await ref.read(gitReadOperationsProvider).getBranches(repo);
    final locals = branches.where((b) => !b.isRemote).toList();
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    final selected = await _showBranchPickerDialog(
      context,
      title: 'Switch branch',
      branches: locals.map((b) => b.name).toList(),
    );
    if (selected == null || !mounted) return;
    await ref.read(gitWriteOperationsProvider).checkout(repo, selected);
    refreshRepo(ref, repo);
  }

  Future<void> _renameBranch(RepoLocation repo) async {
    final branches = await ref.read(gitReadOperationsProvider).getBranches(repo);
    final current = branches.where((b) => b.isCurrent).firstOrNull;
    if (current == null || !mounted) return;
    // ignore: use_build_context_synchronously
    final newName = await _promptText(context, 'Rename current branch',
        label: 'New name', initial: current.name);
    if (newName == null || newName.trim().isEmpty || !mounted) return;
    await ref
        .read(gitWriteOperationsProvider)
        .renameBranch(repo, current.name, newName.trim());
    refreshRepo(ref, repo);
  }

  Future<void> _deleteBranch(RepoLocation repo) async {
    final branches = await ref.read(gitReadOperationsProvider).getBranches(repo);
    final locals = branches.where((b) => !b.isRemote).toList();
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    final selected = await _showBranchPickerDialog(
      context,
      title: 'Delete branch',
      branches: locals.map((b) => b.name).toList(),
    );
    if (selected == null || !mounted) return;
    // ignore: use_build_context_synchronously
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete branch',
      body: 'Delete "$selected"? This cannot be undone.',
      confirmLabel: 'Delete',
      dangerous: true,
    );
    if (!confirmed || !mounted) return;
    await ref
        .read(gitWriteOperationsProvider)
        .deleteBranch(repo, selected, force: true);
    refreshRepo(ref, repo);
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
  final bool enabled;
  final RepoLocation? repo;

  const _StashDropdown({required this.enabled, required this.repo});

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
          await ref.read(gitWriteOperationsProvider).stashApply(repo, 0);
          refreshRepo(ref, repo);
        },
      ),
      AppMenuButton(
        icon: Icons.eject_outlined,
        label: 'Pop latest',
        onPressed: () async {
          _menuController.close();
          await ref.read(gitWriteOperationsProvider).stashPop(repo, 0);
          refreshRepo(ref, repo);
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
        .read(gitWriteOperationsProvider)
        .stashSave(repo, msg?.trim() ?? '');
    refreshRepo(ref, repo);
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
  final bool enabled;
  final RepoLocation? repo;
  const _OpenDropdown({required this.enabled, required this.repo});

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
          _run(() => ref.read(repoLauncherProvider).revealInFiles(repo));
        },
      ),
      AppMenuButton(
        icon: Icons.terminal,
        label: 'Open in terminal',
        onPressed: () {
          _menuController.close();
          _run(() => ref.read(repoLauncherProvider).openInTerminal(repo));
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
          _run(() => ref.read(repoLauncherProvider).openInEditor(
                repo,
                const EditorTarget(
                    id: 'vscode',
                    displayName: 'VS Code',
                    executable: 'code'),
              ));
        },
      ));
    } else {
      for (final editor in editors) {
        items.add(AppMenuButton(
          icon: Icons.code,
          label: 'Open in ${editor.displayName}',
          onPressed: () {
            _menuController.close();
            _run(() =>
                ref.read(repoLauncherProvider).openInEditor(repo, editor));
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
  final String title;
  final List<String> branches;
  const _BranchPickerDialog({required this.title, required this.branches});

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
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

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
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _ToolbarDropdownButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

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
