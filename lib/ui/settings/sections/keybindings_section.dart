import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/settings/key_combination_capture.dart';
import 'package:gitopen/ui/settings/settings_widgets.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class KeybindingsSection extends ConsumerWidget {
  const KeybindingsSection({super.key});

  static const _actions = [
    ('commit', 'Commit'),
    ('commitAndPush', 'Commit & Push'),
    ('fetch', 'Fetch'),
    ('refresh', 'Refresh'),
    ('openRepoSelector', 'Open Repo Selector'),
    ('openSettings', 'Open Settings'),
    ('commandPalette', 'Command Palette'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsPageHeader(
            title: 'Keybindings',
            description:
                'Custom shortcuts. Click Edit to capture a new combination.',
          ),
          SettingsCard(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: [
                for (var i = 0; i < _actions.length; i++)
                  _KeybindingRow(
                    actionId: _actions[i].$1,
                    label: _actions[i].$2,
                    keySet: s.keybindings[_actions[i].$1],
                    isLast: i == _actions.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeybindingRow extends ConsumerWidget {
  const _KeybindingRow({
    required this.actionId,
    required this.label,
    required this.keySet,
    required this.isLast,
  });
  final String actionId;
  final String label;
  final LogicalKeySet? keySet;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final keysLabel = keySet == null
        ? '(unbound)'
        : keySet!.keys
            .map((k) => k.keyLabel.isNotEmpty ? k.keyLabel : k.debugName ?? '?')
            .join(' + ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
      child: Row(
        children: [
          SizedBox(
            width: 220,
            child: Text(label,
                style: TextStyle(color: palette.fg0, fontSize: 12.5)),
          ),
          Expanded(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: palette.bg1,
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                keysLabel,
                style: TextStyle(
                  color: keySet == null ? palette.fg3 : palette.fg0,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AppButton.secondary(
            label: 'Edit',
            onPressed: () async {
              final captured = await showDialog<LogicalKeySet>(
                context: context,
                builder: (_) => KeyCombinationCapture(
                  initial: keySet,
                  onCaptured: (set) => Navigator.pop(context, set),
                  onCancel: () => Navigator.pop(context),
                ),
              );
              if (captured != null) {
                await ref
                    .read(appSettingsProvider.notifier)
                    .setKeybinding(actionId, captured);
              }
            },
          ),
          const SizedBox(width: 6),
          AppButton.secondary(
            label: 'Reset',
            onPressed: () => ref
                .read(appSettingsProvider.notifier)
                .resetKeybinding(actionId),
          ),
        ],
      ),
    );
  }
}
