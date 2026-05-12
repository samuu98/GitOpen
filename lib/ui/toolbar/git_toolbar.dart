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

/// Three-button toolbar for Fetch / Pull / Push.
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToolbarButton(
          icon: Icons.cloud_download_outlined,
          label: 'Fetch',
          enabled: enabled,
          onTap: () => _fetch(active!.location as RepoLocation),
        ),
        _ToolbarButton(
          icon: Icons.south,
          label: 'Pull',
          enabled: enabled,
          onTap: () => _pull(active!.location as RepoLocation),
        ),
        _ToolbarButton(
          icon: Icons.north,
          label: 'Push',
          enabled: enabled,
          onTap: () => _push(active!.location as RepoLocation),
        ),
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
