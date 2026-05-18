import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/providers.dart';
import '../../dialogs/app_dialog.dart';
import '../../theme/app_palette.dart';
import '../settings_widgets.dart';

class UpdatesSection extends ConsumerStatefulWidget {
  const UpdatesSection({super.key});

  @override
  ConsumerState<UpdatesSection> createState() => _UpdatesSectionState();
}

class _UpdatesSectionState extends ConsumerState<UpdatesSection> {
  bool _checking = false;
  String? _status;
  String? _updateVersion;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final s = ref.watch(appSettingsProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsPageHeader(
            title: 'Updates',
            description: 'Stay current with the latest release.',
          ),
          const SettingsSectionTitle('Automatic checks'),
          SettingsCard(
            child: SettingsRow(
              label: 'Check on startup',
              description:
                  'Quietly look for a newer release each time the app opens.',
              divider: false,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Switch(
                  value: s.autoUpdateCheck,
                  onChanged: ref
                      .read(appSettingsProvider.notifier)
                      .setAutoUpdateCheck,
                ),
              ),
            ),
          ),
          const SettingsGap(),
          const SettingsSectionTitle('Manual check'),
          SettingsCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppButton.primary(
                  icon: Icons.refresh,
                  label: _checking ? 'Checking…' : 'Check now',
                  onPressed: _checking ? null : _check,
                ),
                const SizedBox(width: 14),
                if (_status != null)
                  Expanded(
                    child: Text(
                      _status!,
                      style: TextStyle(
                        color: _updateVersion != null
                            ? palette.accentCurrent
                            : palette.fg1,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                if (_updateVersion != null)
                  AppButton.secondary(
                    icon: Icons.open_in_new,
                    label: 'Release page',
                    onPressed: _openReleasePage,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _status = null;
      _updateVersion = null;
    });
    final updater = ref.read(updaterProvider);
    try {
      const currentVersion = '0.1.0';
      final version = await updater.checkForUpdates(currentVersion);
      setState(() {
        _updateVersion = version;
        _status = version != null
            ? 'Update available: v$version'
            : 'You are up to date.';
      });
    } catch (e) {
      setState(() => _status = 'Check failed: $e');
    } finally {
      setState(() => _checking = false);
    }
  }

  Future<void> _openReleasePage() async {
    await ref.read(updaterProvider).openReleasesPage();
  }
}
