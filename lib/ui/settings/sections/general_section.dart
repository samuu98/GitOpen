import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/settings/settings_widgets.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class GeneralSection extends ConsumerWidget {
  const GeneralSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final s = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsPageHeader(
            title: 'General',
            description: 'Appearance, editor, and default git behaviour.',
          ),
          const SettingsSectionTitle('Appearance'),
          SettingsCard(
            child: Column(
              children: [
                SettingsRow(
                  label: 'Theme',
                  description: 'Dark works best with the default palette.',
                  child: SegmentedButton<AppTheme>(
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStateProperty.all(
                          const TextStyle(fontSize: 12)),
                    ),
                    segments: const [
                      ButtonSegment(value: AppTheme.dark, label: Text('Dark')),
                      ButtonSegment(
                        value: AppTheme.light,
                        label: Text('Light'),
                      ),
                    ],
                    selected: {s.theme},
                    onSelectionChanged: (v) => notifier.setTheme(v.first),
                  ),
                ),
                SettingsRow(
                  label: 'Font size',
                  description: 'Used by the diff view and lists.',
                  divider: false,
                  child: SizedBox(
                    width: 90,
                    child: TextFormField(
                      key: ValueKey('font-${s.fontSize}'),
                      initialValue: '${s.fontSize}',
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: palette.fg0, fontSize: 13),
                      decoration: appInputDecoration(context, label: ''),
                      onFieldSubmitted: (v) {
                        final i = int.tryParse(v);
                        if (i != null && i >= 10 && i <= 24) {
                          unawaited(notifier.setFontSize(i));
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SettingsGap(),
          const SettingsSectionTitle('Editor'),
          SettingsCard(
            child: SettingsRow(
              label: 'External editor',
              description:
                  'Used by "Open in editor" — leave empty for system default.',
              divider: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('editor-${s.externalEditorPath}'),
                      initialValue: s.externalEditorPath ?? '',
                      style: TextStyle(color: palette.fg0, fontSize: 13),
                      decoration: appInputDecoration(
                        context,
                        label: '',
                        hint: 'Path to executable',
                      ),
                      onFieldSubmitted: (v) => notifier
                          .setExternalEditorPath(v.isEmpty ? null : v),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: Icon(Icons.folder_open,
                        size: 18, color: palette.fg1),
                    tooltip: 'Browse…',
                    onPressed: () async {
                      const group = XTypeGroup(
                          label: 'Executable', extensions: ['exe']);
                      final f = await openFile(acceptedTypeGroups: [group]);
                      if (f != null) {
                        await notifier.setExternalEditorPath(f.path);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SettingsGap(),
          const SettingsSectionTitle('Git defaults'),
          SettingsCard(
            child: Column(
              children: [
                SettingsRow(
                  label: 'Pull strategy',
                  description: 'Behaviour when pull diverges from upstream.',
                  child: DropdownButton<DefaultPullStrategy>(
                    value: s.defaultPullStrategy,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    style: TextStyle(color: palette.fg0, fontSize: 12.5),
                    items: const [
                      DropdownMenuItem(
                          value: DefaultPullStrategy.merge,
                          child: Text('Merge')),
                      DropdownMenuItem(
                          value: DefaultPullStrategy.rebase,
                          child: Text('Rebase')),
                      DropdownMenuItem(
                          value: DefaultPullStrategy.ffOnly,
                          child: Text('Fast-forward only')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        unawaited(notifier.setDefaultPullStrategy(v));
                      }
                    },
                  ),
                ),
                SettingsRow(
                  label: 'Sign-off by default',
                  description: 'Adds Signed-off-by to every commit message.',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Switch(
                      value: s.commitSignoffDefault,
                      onChanged: notifier.setCommitSignoffDefault,
                    ),
                  ),
                ),
                SettingsRow(
                  label: 'Sign commits (GPG) by default',
                  description:
                      'GPG-signs every commit (git commit -S). Requires a '
                      'configured signing key.',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Switch(
                      value: s.gpgSignByDefault,
                      onChanged: notifier.setGpgSignByDefault,
                    ),
                  ),
                ),
                SettingsRow(
                  label: 'Auto-refresh',
                  description: 'Watch the repository for outside changes '
                      '(commits, checkouts, fetches from a terminal) and '
                      'refresh automatically. Also refreshes when the window '
                      'regains focus.',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Switch(
                      value: s.autoRefresh,
                      onChanged: notifier.setAutoRefresh,
                    ),
                  ),
                ),
                SettingsRow(
                  label: 'Confirm before pull/push',
                  description: 'Ask for confirmation before pulling from or '
                      'pushing to the remote from the toolbar.',
                  divider: false,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Switch(
                      value: s.confirmPushPull,
                      onChanged: notifier.setConfirmPushPull,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
