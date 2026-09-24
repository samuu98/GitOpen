import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/workspaces/workspace.dart';
import 'package:gitopen/ui/common/app_panel_state.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/clone_dialog.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/welcome/workspace_ready.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _busy = false;
  bool _pendingInit = false;
  String? _pendingPath;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final recents = ref.watch(workspaceManagerProvider);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_special, size: 48, color: palette.accentCurrent),
          const SizedBox(height: 16),
          Text(
            'Welcome to GitOpen',
            style: TextStyle(
              color: palette.fg0,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Open or clone a repository to begin.',
            style: TextStyle(color: palette.fg2),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton.primary(
                icon: Icons.folder_open,
                label: 'Open repository',
                onPressed: _busy ? null : _openRepo,
              ),
              const SizedBox(width: 12),
              AppButton.secondary(
                icon: Icons.download,
                label: 'Clone',
                onPressed: () => CloneDialog.show(context),
              ),
              const SizedBox(width: 12),
              AppButton.secondary(
                icon: Icons.fiber_new_outlined,
                label: 'Init',
                onPressed: _busy ? null : _initRepo,
              ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 20),
            const AppLoadingState.detail(),
            const SizedBox(height: 8),
            Text('Opening repository…', style: TextStyle(color: palette.fg2)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 20),
            AppErrorState(
              message: 'Could not load repository',
              detail: _error,
              onRetry: _retry,
            ),
          ],
          if (recents.isNotEmpty)
            _RecentRepos(recents: recents, onOpen: _openPath),
        ],
      ),
    );
  }

  Future<void> _openRepo() async {
    final picker = ref.read(folderPickerProvider);
    final path = await picker.pickFolder('Open repository');
    if (path != null && mounted) await _openPath(path);
  }

  /// `git init` in a picked folder, then open it as a workspace. Failures are
  /// surfaced through the shared operations/toast system, like every other git
  /// action — not a one-off SnackBar.
  Future<void> _initRepo() async {
    final picker = ref.read(folderPickerProvider);
    final path = await picker.pickFolder('Initialize repository');
    if (path == null || !mounted) return;
    await _openPath(path, initialize: true);
  }

  Future<void> _retry() async {
    final path = _pendingPath;
    if (path == null) return;
    await _openPath(path, initialize: _pendingInit, retry: true);
  }

  Future<void> _openPath(
    String path, {
    bool initialize = false,
    bool retry = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _pendingPath = path;
      _pendingInit = initialize;
    });
    final ops = ref.read(operationsProvider.notifier);
    final active = ref.read(activeWorkspaceIdProvider.notifier);
    final manager = ref.read(workspaceManagerProvider.notifier);
    final write = ref.read(gitWriteOperationsProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final opId = ops.start(
      OpKind.other,
      initialize ? 'Initialize repository' : 'Open repository',
    );
    try {
      if (initialize) {
        final result = await write.initRepo(path);
        if (result case GitFailure(:final message)) throw StateError(message);
        _pendingInit = false;
      }
      final ws = await manager.open(path);
      if (retry) {
        await retryWorkspaceReady(container, ws.location);
      } else {
        await container.read(workspaceReadyProvider(ws.location).future);
      }
      ops.finishSuccess(opId);
      active.state = ws.location.id;
    } on Object catch (error) {
      ops.finishFailure(opId, '$error');
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// The known-repository catalog, shown beneath the actions so a returning user
/// can re-open a recent repo in one click instead of re-picking the folder.
class _RecentRepos extends StatelessWidget {
  const _RecentRepos({required this.recents, required this.onOpen});
  final List<Workspace> recents;
  final Future<void> Function(String) onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final shown = recents.take(6).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: SizedBox(
        width: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                'RECENT',
                style: TextStyle(
                  color: palette.fg3,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
            ),
            for (final w in shown)
              _RecentTile(
                workspace: w,
                onOpen: () => unawaited(onOpen(w.location.path)),
              ),
          ],
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.workspace, required this.onOpen});
  final Workspace workspace;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final loc = workspace.location;
    return Material(
      color: Colors.transparent,
      borderRadius: AppRadii.of(context).rowRadius,
      child: InkWell(
        onTap: onOpen,
        borderRadius: AppRadii.of(context).rowRadius,
        hoverColor: palette.bg3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, size: 15, color: palette.fg2),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loc.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.fg0,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      loc.path,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.fg3, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
