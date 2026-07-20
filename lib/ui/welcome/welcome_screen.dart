import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/workspaces/workspace.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/clone_dialog.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                onPressed: () => _openRepo(ref),
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
                onPressed: () => _initRepo(ref),
              ),
            ],
          ),
          if (recents.isNotEmpty) _RecentRepos(recents: recents),
        ],
      ),
    );
  }

  Future<void> _openRepo(WidgetRef ref) async {
    final picker = ref.read(folderPickerProvider);
    final path = await picker.pickFolder('Open repository');
    if (path == null) return;
    final ops = ref.read(operationsProvider.notifier);
    final opId = ops.start(OpKind.other, 'Open repository');
    final manager = ref.read(workspaceManagerProvider.notifier);
    try {
      final ws = await manager.open(path);
      ops.finishSuccess(opId);
      ref.read(activeWorkspaceIdProvider.notifier).state = ws.location.id;
    } on Object catch (error) {
      ops.finishFailure(opId, '$error');
    }
  }

  /// `git init` in a picked folder, then open it as a workspace. Failures are
  /// surfaced through the shared operations/toast system, like every other git
  /// action — not a one-off SnackBar.
  Future<void> _initRepo(WidgetRef ref) async {
    final picker = ref.read(folderPickerProvider);
    final path = await picker.pickFolder('Initialize repository');
    if (path == null) return;
    final ops = ref.read(operationsProvider.notifier);
    final opId = ops.start(OpKind.other, 'Initialize repository');
    final result = await ref.read(gitWriteOperationsProvider).initRepo(path);
    if (result case GitFailure(:final message)) {
      ops.finishFailure(opId, message);
      return;
    }
    final manager = ref.read(workspaceManagerProvider.notifier);
    try {
      final ws = await manager.open(path);
      ops.finishSuccess(opId);
      ref.read(activeWorkspaceIdProvider.notifier).state = ws.location.id;
    } on Object catch (error) {
      ops.finishFailure(opId, '$error');
    }
  }
}

/// The known-repository catalog, shown beneath the actions so a returning user
/// can re-open a recent repo in one click instead of re-picking the folder.
class _RecentRepos extends ConsumerWidget {
  const _RecentRepos({required this.recents});
  final List<Workspace> recents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                onOpen: () => unawaited(_openRecent(ref, w)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRecent(WidgetRef ref, Workspace workspace) async {
    final ops = ref.read(operationsProvider.notifier);
    final opId = ops.start(OpKind.other, 'Open repository');
    try {
      final opened = await ref
          .read(workspaceManagerProvider.notifier)
          .open(workspace.location.path);
      ref.read(activeWorkspaceIdProvider.notifier).state = opened.location.id;
      ops.finishSuccess(opId);
    } on Object catch (error) {
      ops.finishFailure(opId, '$error');
    }
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
