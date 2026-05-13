import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../application/providers.dart';
import '../../theme/app_palette.dart';

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
  void dispose() { _ctl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('GitHub OAuth App', style: TextStyle(color: p.fg0, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(
          'To enable GitHub Device Flow sign-in, register an OAuth App at github.com/settings/applications/new (any callback URL works — Device Flow ignores it). Paste the Client ID below.',
          style: TextStyle(color: p.fg2, fontSize: 12),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _ctl,
          decoration: const InputDecoration(labelText: 'Client ID'),
          onChanged: (v) => ref.read(appSettingsProvider.notifier).setGithubClientId(v.isEmpty ? null : v),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          icon: const Icon(Icons.open_in_new, size: 14),
          label: const Text('Register a new OAuth App on GitHub'),
          onPressed: () => launchUrl(Uri.parse('https://github.com/settings/applications/new')),
        ),
      ]),
    );
  }
}
