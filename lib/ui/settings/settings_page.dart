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

  static const _groups = <(_NavGroup, List<SettingsSectionId>)>[
    (
      _NavGroup('Application'),
      [SettingsSectionId.general, SettingsSectionId.keybindings]
    ),
    (
      _NavGroup('Identity'),
      [
        SettingsSectionId.gitIdentity,
        SettingsSectionId.authentication,
        SettingsSectionId.github,
      ]
    ),
    (
      _NavGroup('System'),
      [SettingsSectionId.updates, SettingsSectionId.about]
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      color: palette.bg1,
      child: Row(
        children: [
          _Sidebar(
            selected: _selected,
            groups: _groups,
            onSelect: (s) => setState(() => _selected = s),
            onClose: () =>
                ref.read(settingsOpenProvider.notifier).state = false,
          ),
          Expanded(
            child: Container(
              color: palette.bg1,
              child: _renderSection(_selected),
            ),
          ),
        ],
      ),
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

class _NavGroup {
  final String title;
  const _NavGroup(this.title);
}

class _Sidebar extends StatelessWidget {
  final SettingsSectionId selected;
  final List<(_NavGroup, List<SettingsSectionId>)> groups;
  final ValueChanged<SettingsSectionId> onSelect;
  final VoidCallback onClose;

  const _Sidebar({
    required this.selected,
    required this.groups,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: palette.bg2,
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(onClose: onClose),
          Divider(height: 1, thickness: 1, color: palette.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final (group, items) in groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Text(
                      group.title.toUpperCase(),
                      style: TextStyle(
                        color: palette.fg3,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                  for (final id in items)
                    _NavItem(
                      section: id,
                      selected: id == selected,
                      onTap: () => onSelect(id),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onClose;
  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        children: [
          Icon(Icons.tune, size: 16, color: palette.fg1),
          const SizedBox(width: 8),
          Text(
            'Settings',
            style: TextStyle(
              color: palette.fg0,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _CloseButton(onTap: onClose),
        ],
      ),
    );
  }
}

class _CloseButton extends StatefulWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: 'Close settings',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _hover ? palette.bg4 : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(Icons.close,
                size: 14, color: _hover ? palette.fg0 : palette.fg1),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final SettingsSectionId section;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (icon, label) = _meta(widget.section);
    final fg = widget.selected
        ? palette.fg0
        : (_hover ? palette.fg0 : palette.fg1);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(
            color: widget.selected
                ? palette.bgAccent.withValues(alpha: 0.30)
                : (_hover ? palette.bg3 : Colors.transparent),
            borderRadius: BorderRadius.circular(5),
            border: widget.selected
                ? Border.all(color: palette.bgAccent)
                : Border.all(color: Colors.transparent),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12.5,
                  fontWeight: widget.selected
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (IconData, String) _meta(SettingsSectionId s) {
    return switch (s) {
      SettingsSectionId.general => (Icons.tune, 'General'),
      SettingsSectionId.gitIdentity =>
        (Icons.fingerprint, 'Git Identity'),
      SettingsSectionId.authentication =>
        (Icons.key_outlined, 'Authentication'),
      SettingsSectionId.keybindings =>
        (Icons.keyboard_outlined, 'Keybindings'),
      SettingsSectionId.github => (Icons.code, 'GitHub'),
      SettingsSectionId.updates => (Icons.system_update, 'Updates'),
      SettingsSectionId.about => (Icons.info_outline, 'About'),
    };
  }
}
