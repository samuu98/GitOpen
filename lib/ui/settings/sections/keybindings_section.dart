import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/providers.dart';
import '../../theme/app_palette.dart';
import '../key_combination_capture.dart';

class KeybindingsSection extends ConsumerWidget {
  const KeybindingsSection({super.key});

  static const _actions = [
    ('commit', 'Commit'),
    ('commitAndPush', 'Commit & Push'),
    ('fetch', 'Fetch'),
    ('refresh', 'Refresh'),
    ('openRepoSelector', 'Open Repo Selector'),
    ('openSettings', 'Open Settings'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final s = ref.watch(appSettingsProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Keybindings', style: TextStyle(color: p.fg0, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        for (final (id, label) in _actions)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
            child: Row(children: [
              SizedBox(width: 200, child: Text(label, style: TextStyle(color: p.fg0, fontSize: 13))),
              Expanded(child: Text(
                s.keybindings[id]?.keys.map((k) => k.keyLabel.isNotEmpty ? k.keyLabel : k.debugName ?? '?').join(' + ') ?? '(unbound)',
                style: TextStyle(color: p.fg1, fontFamily: 'monospace', fontSize: 12),
              )),
              TextButton(
                onPressed: () async {
                  final captured = await showDialog<LogicalKeySet>(
                    context: context,
                    builder: (_) => KeyCombinationCapture(
                      initial: s.keybindings[id],
                      onCaptured: (set) => Navigator.pop(context, set),
                      onCancel: () => Navigator.pop(context),
                    ),
                  );
                  if (captured != null) {
                    await ref.read(appSettingsProvider.notifier).setKeybinding(id, captured);
                  }
                },
                child: const Text('Edit'),
              ),
              TextButton(
                onPressed: () => ref.read(appSettingsProvider.notifier).resetKeybinding(id),
                child: const Text('Reset'),
              ),
            ]),
          ),
      ]),
    );
  }
}
