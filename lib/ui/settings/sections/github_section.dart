import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../application/providers.dart';
import '../../dialogs/app_dialog.dart';
import '../../theme/app_palette.dart';
import '../settings_widgets.dart';

class GitHubSection extends ConsumerStatefulWidget {
  const GitHubSection({super.key});
  @override
  ConsumerState<GitHubSection> createState() => _State();
}

class _State extends ConsumerState<GitHubSection> {
  late final TextEditingController _ctl;

  @override
  void initState() {
    super.initState();
    final s = ref.read(appSettingsProvider);
    _ctl = TextEditingController(text: s.githubClientId ?? '');
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsPageHeader(
            title: 'GitHub',
            description: 'OAuth integration for in-app sign-in.',
          ),
          const SettingsSectionTitle('OAuth Device Flow'),
          SettingsCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'To enable in-app GitHub sign-in, register an OAuth App on '
                  'GitHub (any callback URL works — Device Flow ignores it) '
                  'and paste the Client ID below.',
                  style: TextStyle(
                      color: palette.fg2, fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _ctl,
                  style: TextStyle(color: palette.fg0, fontSize: 13),
                  decoration:
                      appInputDecoration(context, label: 'Client ID'),
                  onChanged: (v) => ref
                      .read(appSettingsProvider.notifier)
                      .setGithubClientId(v.isEmpty ? null : v),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton.secondary(
                    icon: Icons.open_in_new,
                    label: 'Register a new OAuth App on GitHub',
                    onPressed: () => launchUrl(Uri.parse(
                        'https://github.com/settings/applications/new')),
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
