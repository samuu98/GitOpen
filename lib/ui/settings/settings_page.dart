import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/settings/settings_open_provider.dart';
import 'package:gitopen/ui/common/app_icon_button.dart';
import 'package:gitopen/ui/settings/sections/about_section.dart';
import 'package:gitopen/ui/settings/sections/authentication_section.dart';
import 'package:gitopen/ui/settings/sections/general_section.dart';
import 'package:gitopen/ui/settings/sections/git_identity_section.dart';
import 'package:gitopen/ui/settings/sections/github_section.dart';
import 'package:gitopen/ui/settings/sections/keybindings_section.dart';
import 'package:gitopen/ui/settings/sections/updates_section.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

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
      [SettingsSectionId.general, SettingsSectionId.keybindings],
    ),
    (
      _NavGroup('Identity'),
      [
        SettingsSectionId.gitIdentity,
        SettingsSectionId.authentication,
        SettingsSectionId.github,
      ],
    ),
    (_NavGroup('System'), [SettingsSectionId.updates, SettingsSectionId.about]),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ColoredBox(
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
            child: ColoredBox(
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
  const _NavGroup(this.title);
  final String title;
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selected,
    required this.groups,
    required this.onSelect,
    required this.onClose,
  });
  final SettingsSectionId selected;
  final List<(_NavGroup, List<SettingsSectionId>)> groups;
  final ValueChanged<SettingsSectionId> onSelect;
  final VoidCallback onClose;

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
                      style: AppTypography.of(context).caption.copyWith(
                        color: palette.fg3,
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
  const _Header({required this.onClose});
  final VoidCallback onClose;

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

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppIconButton(
      icon: Icons.close,
      tooltip: 'Close settings',
      onPressed: onTap,
      size: 24,
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });
  final SettingsSectionId section;
  final bool selected;
  final VoidCallback onTap;

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
    return Semantics(
      button: true,
      selected: widget.selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          excludeFromSemantics: true,
          onHover: (hovered) => setState(() => _hover = hovered),
          borderRadius: BorderRadius.circular(5),
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
                  style: AppTypography.of(context).body.copyWith(
                    color: fg,
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  (IconData, String) _meta(SettingsSectionId s) {
    return switch (s) {
      SettingsSectionId.general => (Icons.tune, 'General'),
      SettingsSectionId.gitIdentity => (Icons.fingerprint, 'Git Identity'),
      SettingsSectionId.authentication => (
        Icons.key_outlined,
        'Authentication',
      ),
      SettingsSectionId.keybindings => (Icons.keyboard_outlined, 'Keybindings'),
      SettingsSectionId.github => (Icons.code, 'GitHub'),
      SettingsSectionId.updates => (Icons.system_update, 'Updates'),
      SettingsSectionId.about => (Icons.info_outline, 'About'),
    };
  }
}
