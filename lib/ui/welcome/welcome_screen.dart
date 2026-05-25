import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/providers.dart';
import '../dialogs/clone_dialog.dart';
import '../theme/app_palette.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/icon/app_icon.png',
            width: 80,
            height: 80,
            filterQuality: FilterQuality.none, // preserve pixel-art edges
          ),
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
}
