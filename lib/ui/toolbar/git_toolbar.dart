import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/active_workspace_provider.dart';
import '../../application/auth/auth_profile.dart';
import '../../application/git/auth_spec.dart';
import '../../application/git/git_write_operations.dart';
import '../../application/launcher/repo_launcher.dart';
import '../../application/operations/running_operation.dart';
import '../../application/providers.dart';
import '../../application/settings/app_settings.dart';
import '../../domain/repositories/repo_location.dart';
import '../../infrastructure/git/git_process_runner.dart';
import '../dialogs/account_switcher_dialog.dart';
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
    Stream<dynamic> Function(AuthSpec? auth) streamFactory, {
    AuthProfile? profile,
  }) async {
    final ops = ref.read(operationsProvider.notifier);
    final id = ops.start(kind, label, repo: repo);
    profile ??= await ref.read(authResolverProvider).resolveForRepo(repo);
    try {
      await for (final ev in streamFactory(profile?.spec)) {
        ops.updateProgress(
          id,
          (ev as dynamic).fraction as double?,
          (ev as dynamic).phase as String,
        );
      }
      ops.finishSuccess(id);
      ref.invalidate(gitReadOperationsProvider);
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
    Stream<dynamic> Function(AuthSpec? auth) streamFactory, {
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
      MenuItemButton(
        leadingIcon: const Icon(Icons.add, size: 14),
        onPressed: () async {
          _menuController.close();
          if (!mounted) return;
          // ignore: use_build_context_synchronously
          await BranchCreateDialog.show(context, repo);
          ref.invalidate(gitReadOperationsProvider);
        },
        child: const Text('New branch from HEAD'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.swap_horiz, size: 14),
        onPressed: () async {
          _menuController.close();
          if (!mounted) return;
          await _switchBranch(repo);
        },
        child: const Text('Switch branch…'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.drive_file_rename_outline, size: 14),
        onPressed: () async {
          _menuController.close();
          if (!mounted) return;
          await _renameBranch(repo);
        },
        child: const Text('Rename current branch…'),
      ),
      const Divider(height: 1),
      MenuItemButton(
        leadingIcon: const Icon(Icons.delete_outline, size: 14),
        onPressed: () async {
          _menuController.close();
          if (!mounted) return;
          await _deleteBranch(repo);
        },
        child: const Text('Delete branch…'),
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
    ref.invalidate(gitReadOperationsProvider);
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
    ref.invalidate(gitReadOperationsProvider);
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
    ref.invalidate(gitReadOperationsProvider);
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
      {required String label, String? initial}) async {
    final ctl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctl.text),
              child: const Text('OK')),
        ],
      ),
    );
    ctl.dispose();
    return result;
  }
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
      MenuItemButton(
        leadingIcon: const Icon(Icons.save_outlined, size: 14),
        onPressed: () async {
          _menuController.close();
          if (!context.mounted) return;
          await _stashSave(repo);
        },
        child: const Text('Stash changes…'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.arrow_downward, size: 14),
        onPressed: () async {
          _menuController.close();
          await ref.read(gitWriteOperationsProvider).stashApply(repo, 0);
          ref.invalidate(gitReadOperationsProvider);
        },
        child: const Text('Apply latest'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.eject_outlined, size: 14),
        onPressed: () async {
          _menuController.close();
          await ref.read(gitWriteOperationsProvider).stashPop(repo, 0);
          ref.invalidate(gitReadOperationsProvider);
        },
        child: const Text('Pop latest'),
      ),
      const Divider(height: 1),
      MenuItemButton(
        leadingIcon: const Icon(Icons.list_outlined, size: 14),
        onPressed: () async {
          _menuController.close();
          if (!context.mounted) return;
          await _viewStashes(repo);
        },
        child: const Text('View stashes…'),
      ),
    ];
  }

  Future<void> _stashSave(RepoLocation repo) async {
    // ignore: use_build_context_synchronously
    final msg = await _promptText(context, 'Stash changes',
        label: 'Message (optional)');
    if (!mounted) return;
    await ref
        .read(gitWriteOperationsProvider)
        .stashSave(repo, msg?.trim() ?? '');
    ref.invalidate(gitReadOperationsProvider);
  }

  Future<void> _viewStashes(RepoLocation repo) async {
    final stashes = await ref.read(gitReadOperationsProvider).getStashes(repo);
    if (!mounted) return;
    // ignore: use_build_context_synchronously
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stashes'),
        content: stashes.isEmpty
            ? const Text('No stashes.')
            : SizedBox(
                width: 400,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: stashes.length,
                  itemBuilder: (_, i) {
                    final s = stashes[i];
                    return ListTile(
                      dense: true,
                      title: Text('stash@{${s.index}}'),
                      subtitle: Text(s.message),
                    );
                  },
                ),
              ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Future<String?> _promptText(BuildContext context, String title,
      {required String label, String? initial}) async {
    final ctl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctl.text),
              child: const Text('OK')),
        ],
      ),
    );
    ctl.dispose();
    return result;
  }
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
      MenuItemButton(
        leadingIcon: const Icon(Icons.folder_open, size: 14),
        onPressed: () {
          _menuController.close();
          _run(() => ref.read(repoLauncherProvider).revealInFiles(repo));
        },
        child: const Text('Show in file explorer'),
      ),
      MenuItemButton(
        leadingIcon: const Icon(Icons.terminal, size: 14),
        onPressed: () {
          _menuController.close();
          _run(() => ref.read(repoLauncherProvider).openInTerminal(repo));
        },
        child: const Text('Open in terminal'),
      ),
      const Divider(height: 1),
    ];

    if (editors.isEmpty) {
      items.add(MenuItemButton(
        leadingIcon: const Icon(Icons.code, size: 14),
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
        child: const Text('Open in VS Code'),
      ));
    } else {
      for (final editor in editors) {
        items.add(MenuItemButton(
          leadingIcon: const Icon(Icons.code, size: 14),
          onPressed: () {
            _menuController.close();
            _run(() =>
                ref.read(repoLauncherProvider).openInEditor(repo, editor));
          },
          child: Text('Open in ${editor.displayName}'),
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
    final filtered = widget.branches
        .where((b) => b.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        height: 320,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                  hintText: 'Filter…', prefixIcon: Icon(Icons.search, size: 16)),
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final b = filtered[i];
                  return ListTile(
                    dense: true,
                    selected: _selected == b,
                    title: Text(b, style: const TextStyle(fontSize: 13)),
                    onTap: () => setState(() => _selected = b),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _selected != null ? () => Navigator.pop(context, _selected) : null,
          child: const Text('OK'),
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
