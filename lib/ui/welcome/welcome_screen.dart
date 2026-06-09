import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/dialogs/clone_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
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
          Row(mainAxisSize: MainAxisSize.min, children: [
            ElevatedButton.icon(
              onPressed: () => _openRepo(context, ref),
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Open repository'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => CloneDialog.show(context),
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Clone'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => _initRepo(context, ref),
              icon: const Icon(Icons.fiber_new_outlined, size: 16),
              label: const Text('Init'),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _openRepo(BuildContext context, WidgetRef ref) async {
    final picker = ref.read(folderPickerProvider);
    final path = await picker.pickFolder('Open repository');
    if (path == null) return;
    final manager = ref.read(workspaceManagerProvider.notifier);
    final ws = await manager.open(path);
    ref.read(activeWorkspaceIdProvider.notifier).state = ws.location.id;
  }

  /// `git init` in a picked folder, then open it as a workspace.
  Future<void> _initRepo(BuildContext context, WidgetRef ref) async {
    final picker = ref.read(folderPickerProvider);
    final path = await picker.pickFolder('Initialize repository');
    if (path == null) return;
    final result = await ref.read(gitWriteOperationsProvider).initRepo(path);
    if (result case GitFailure(:final message)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Init failed: $message'),
        backgroundColor: AppPalette.of(context).accentErr,
      ));
      return;
    }
    final manager = ref.read(workspaceManagerProvider.notifier);
    final ws = await manager.open(path);
    ref.read(activeWorkspaceIdProvider.notifier).state = ws.location.id;
  }
}
