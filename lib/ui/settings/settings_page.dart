import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/settings/settings_open_provider.dart';
import '../theme/app_palette.dart';
import 'sections/about_section.dart';
import 'sections/authentication_section.dart';
import 'sections/general_section.dart';
import 'sections/git_identity_section.dart';
import 'sections/github_section.dart';
import 'sections/keybindings_section.dart';
import 'sections/updates_section.dart';

enum SettingsSectionId {
  general,
  gitIdentity,
  authentication,
  keybindings,
  github,
  updates,
  about,
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _State();
}

class _State extends ConsumerState<SettingsPage> {
  SettingsSectionId _selected = SettingsSectionId.general;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      color: p.bg1,
      child: Row(children: [
        Container(
          width: 220,
          color: p.bg2,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Text(
                  'Settings',
                  style: TextStyle(color: p.fg0, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: p.fg1),
                  onPressed: () => ref.read(settingsOpenProvider.notifier).state = false,
                ),
              ]),
            ),
            for (final s in SettingsSectionId.values)
              _NavItem(
                section: s,
                selected: s == _selected,
                onSelect: () => setState(() => _selected = s),
              ),
          ]),
        ),
        Expanded(child: _renderSection(_selected)),
      ]),
    );
  }

  Widget _renderSection(SettingsSectionId s) {
    return switch (s) {
      SettingsSectionId.general => const GeneralSection(),
      SettingsSectionId.gitIdentity => const GitIdentitySection(),
      SettingsSectionId.authentication => const AuthenticationSection(),
      SettingsSectionId.keybindings => const KeybindingsSection(),
      SettingsSectionId.github => const GitHubSection(),
      SettingsSectionId.updates => const UpdatesSection(),
      SettingsSectionId.about => const AboutSection(),
    };
  }
}

class _NavItem extends StatelessWidget {
  final SettingsSectionId section;
  final bool selected;
  final VoidCallback onSelect;

  const _NavItem({required this.section, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return InkWell(
      onTap: onSelect,
      child: Container(
        color: selected ? p.bg4 : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text(
          _label(section),
          style: TextStyle(color: selected ? p.fg0 : p.fg1, fontSize: 13),
        ),
      ),
    );
  }

  String _label(SettingsSectionId s) {
    return switch (s) {
      SettingsSectionId.general => 'General',
      SettingsSectionId.gitIdentity => 'Git Identity',
      SettingsSectionId.authentication => 'Authentication',
      SettingsSectionId.keybindings => 'Keybindings',
      SettingsSectionId.github => 'GitHub',
      SettingsSectionId.updates => 'Updates',
      SettingsSectionId.about => 'About',
    };
  }
}
