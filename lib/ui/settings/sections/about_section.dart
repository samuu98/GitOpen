import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/settings/settings_widgets.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class AboutSection extends ConsumerWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final version = ref.watch(appVersionProvider).value ?? '…';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsPageHeader(
            title: 'About',
            description: 'Build information and credits.',
          ),
          SettingsCard(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: palette.bgAccent.withValues(alpha: 0.30),
                    border: Border.all(color: palette.bgAccent),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.account_tree,
                      size: 28, color: palette.accentCurrent),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GitOpen',
                        style: TextStyle(
                          color: palette.fg0,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Cross-platform desktop git client',
                        style:
                            TextStyle(color: palette.fg2, fontSize: 12.5),
                      ),
                      const SizedBox(height: 14),
                      _Meta(label: 'Version', value: version),
                      const SizedBox(height: 4),
                      const _Meta(label: 'License', value: 'MIT'),
                      const SizedBox(height: 4),
                      const _Meta(label: 'Fork', value: 'zN3utr4l'),
                    ],
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

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
              color: palette.fg3,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Text(value,
            style: TextStyle(color: palette.fg1, fontSize: 12.5)),
      ],
    );
  }
}
