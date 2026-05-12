import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/providers.dart';
import '../dialogs/clone_dialog.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_special, size: 48, color: Color(0xFF4EC9B0)),
          const SizedBox(height: 16),
          const Text(
            'Welcome to GitOpen',
            style: TextStyle(
              color: Color(0xFFD4D4D4),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Open or clone a repository to begin.',
            style: TextStyle(color: Color(0xFF888892)),
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
