import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/active_workspace_provider.dart';
import '../../application/git/auth_spec.dart';
import '../../application/git/git_write_operations.dart';
import '../../application/operations/running_operation.dart';
import '../../application/providers.dart';
import '../../domain/repositories/repo_location.dart';
import '../dialogs/auth_dialog.dart';
import '../dialogs/branch_create_dialog.dart';
import '../dialogs/confirm_dialog.dart';

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
      ],
    );
  }

  Future<void> _fetch(RepoLocation repo) => _runStream(
        OpKind.fetch,
        'Fetching origin',
        repo,
        (auth) => ref.read(gitWriteOperationsProvider).fetch(repo, auth: auth),
      );

  Future<void> _pull(RepoLocation repo) => _runStream(
        OpKind.pull,
        'Pulling',
        repo,
        (auth) => ref.read(gitWriteOperationsProvider).pull(repo, PullStrategy.merge, auth: auth),
      );

  Future<void> _push(RepoLocation repo) => _runStream(
        OpKind.push,
        'Pushing',
        repo,
        (auth) => ref.read(gitWriteOperationsProvider).push(repo, auth: auth),
      );

  /// Runs a streaming git operation, tracking it in [operationsProvider].
  ///
  /// If the stream throws with an auth-related error the user is prompted
  /// with [AuthDialog].  On success the operation is retried once with the
  /// new credential.  [streamFactory] accepts an optional [AuthSpec] so the
  /// retry can inject it.
  Future<void> _runStream(
    OpKind kind,
    String label,
    RepoLocation repo,
    Stream<dynamic> Function(AuthSpec? auth) streamFactory, {
    AuthSpec? auth,
  }) async {
    final ops = ref.read(operationsProvider.notifier);
    final id = ops.start(kind, label, repo: repo);
    try {
      await for (final ev in streamFactory(auth)) {
        ops.updateProgress(
          id,
          (ev as dynamic).fraction as double?,
          (ev as dynamic).phase as String,
        );
      }
      ops.finishSuccess(id);
      ref.invalidate(gitReadOperationsProvider);
    } catch (e) {
      final msg = e.toString();
      if (_isAuthError(msg)) {
        ops.finishFailure(id, 'Authentication required');
        await _promptAuthAndRetry(kind, label, repo, streamFactory, msg);
      } else {
        ops.finishFailure(id, msg);
      }
    }
  }

  /// Detects common auth-failure signals from git stderr / exception messages.
  bool _isAuthError(String msg) {
    final lower = msg.toLowerCase();
    return lower.contains('authentication failed') ||
        lower.contains('auth') ||
        lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('invalid username or password') ||
        lower.contains('remote: denied') ||
        lower.contains('permission denied');
  }

  /// Derives the git host from the remote URL stored in the repo.
  ///
  /// Checks `git remote get-url origin` and matches common URL forms:
  ///   https://github.com/...  → github.com
  ///   git@github.com:...      → github.com
  /// Falls back to 'github.com' if detection fails.
  Future<String> _hostFromRepo(RepoLocation repo) async {
    try {
      final result = await Process.run(
        'git',
        ['remote', 'get-url', 'origin'],
        workingDirectory: repo.path,
      );
      if (result.exitCode == 0) {
        final url = (result.stdout as String).trim();
        // https://hostname/...
        final httpsMatch = RegExp(r'^https?://([^/]+)').firstMatch(url);
        if (httpsMatch != null) return httpsMatch.group(1)!;
        // git@hostname:...
        final sshMatch = RegExp(r'^git@([^:]+):').firstMatch(url);
        if (sshMatch != null) return sshMatch.group(1)!;
      }
    } catch (_) {
      // ignore — fall through to default
    }
    return 'github.com';
  }

  /// Shows [AuthDialog] for the detected host and, if the user provides
  /// credentials, re-runs the same operation with the new [AuthSpec].
  Future<void> _promptAuthAndRetry(
    OpKind kind,
    String label,
    RepoLocation repo,
    Stream<dynamic> Function(AuthSpec? auth) streamFactory,
    String originalError,
  ) async {
    if (!mounted) return;
    final host = await _hostFromRepo(repo);
    if (!mounted) return;
    final spec = await AuthDialog.show(context, host);
    if (spec == null) return; // user cancelled
    // Retry once with the new credential (no further auth-retry loop).
    await _runStream(kind, label, repo, streamFactory, auth: spec);
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
              Icon(icon, size: 14, color: const Color(0xFFB8B8BC)),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFD4D4D4),
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
              Icon(icon, size: 14, color: const Color(0xFFB8B8BC)),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFD4D4D4),
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(Icons.expand_more, size: 12, color: Color(0xFF888892)),
            ],
          ),
        ),
      ),
    );
  }
}
