import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/settings/app_settings.dart';
import '../../../application/providers.dart';
import '../../theme/app_palette.dart';

class GeneralSection extends ConsumerWidget {
  const GeneralSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _SectionHeader('Appearance'),
        _Row(label: 'Theme', child: SegmentedButton<AppTheme>(
          segments: const [
            ButtonSegment(value: AppTheme.dark, label: Text('Dark')),
            ButtonSegment(value: AppTheme.light, label: Text('Light')),
          ],
          selected: {s.theme},
          onSelectionChanged: (v) => notifier.setTheme(v.first),
        )),
        _Row(label: 'Font size', child: SizedBox(
          width: 80,
          child: TextFormField(
            initialValue: '${s.fontSize}',
            keyboardType: TextInputType.number,
            onFieldSubmitted: (v) {
              final i = int.tryParse(v);
              if (i != null && i >= 10 && i <= 24) notifier.setFontSize(i);
            },
          ),
        )),
        const SizedBox(height: 24),
        _SectionHeader('Editor'),
        _Row(label: 'External editor', child: Row(children: [
          Expanded(child: TextFormField(
            initialValue: s.externalEditorPath ?? '',
            onFieldSubmitted: (v) => notifier.setExternalEditorPath(v.isEmpty ? null : v),
            decoration: const InputDecoration(hintText: 'Leave empty for system default'),
          )),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: () async {
              const group = XTypeGroup(label: 'Executable', extensions: ['exe']);
              final f = await openFile(acceptedTypeGroups: [group]);
              if (f != null) notifier.setExternalEditorPath(f.path);
            },
          ),
        ])),
        const SizedBox(height: 24),
        _SectionHeader('Git defaults'),
        _Row(label: 'Pull strategy', child: DropdownButton<DefaultPullStrategy>(
          value: s.defaultPullStrategy,
          items: const [
            DropdownMenuItem(value: DefaultPullStrategy.merge, child: Text('Merge')),
            DropdownMenuItem(value: DefaultPullStrategy.rebase, child: Text('Rebase')),
            DropdownMenuItem(value: DefaultPullStrategy.ffOnly, child: Text('Fast-forward only')),
          ],
          onChanged: (v) { if (v != null) notifier.setDefaultPullStrategy(v); },
        )),
        _Row(label: 'Sign-off by default', child: Switch(
          value: s.commitSignoffDefault,
          onChanged: notifier.setCommitSignoffDefault,
        )),
      ]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text.toUpperCase(), style: TextStyle(
        color: p.fg2, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5,
      )),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final Widget child;
  const _Row({required this.label, required this.child});
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(children: [
        SizedBox(width: 180, child: Text(label, style: TextStyle(color: p.fg1, fontSize: 13))),
        Expanded(child: child),
      ]),
    );
  }
}
