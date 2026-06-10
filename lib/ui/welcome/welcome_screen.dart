import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/providers.dart';
import '../dialogs/app_dialog.dart';
import '../dialogs/clone_dialog.dart';
import '../theme/app_palette.dart';
import '../theme/app_typography.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final typo = AppTypography.of(context);
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
            style: typo.heading.copyWith(color: palette.fg0, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Open or clone a repository to begin.',
            style: typo.body.copyWith(color: palette.fg2),
          ),
          const SizedBox(height: 24),
          Row(mainAxisSize: MainAxisSize.min, children: [
            AppButton.primary(
              label: 'Open repository',
              icon: Icons.folder_open,
              onPressed: () => _openRepo(context, ref),
            ),
            const SizedBox(width: 12),
            AppButton.secondary(
              label: 'Clone',
              icon: Icons.download,
              onPressed: () => CloneDialog.show(context),
            ),
          ]),
          const SizedBox(height: 28),
          Text(
            'Tip: press Ctrl+P anywhere for the command palette',
            style: typo.bodySmall.copyWith(color: palette.fg3),
          ),
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
