import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/updates/app_release.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/settings/settings_widgets.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class UpdatesSection extends ConsumerStatefulWidget {
  const UpdatesSection({super.key});

  @override
  ConsumerState<UpdatesSection> createState() => _UpdatesSectionState();
}

class _UpdatesSectionState extends ConsumerState<UpdatesSection> {
  bool _checking = false;
  bool _downloading = false;
  bool _launched = false;
  double _progress = 0;
  String? _status;
  AppRelease? _update;
  ReleaseAsset? _installer;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final s = ref.watch(appSettingsProvider);
    final version = ref.watch(appVersionProvider).valueOrNull;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsPageHeader(
            title: 'Updates',
            description: version != null
                ? 'Installed version: v$version'
                : 'Stay current with the latest release.',
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppButton.primary(
                      icon: Icons.refresh,
                      label: _checking ? 'Checking…' : 'Check now',
                      onPressed: _checking || _downloading ? null : _check,
                    ),
                    const SizedBox(width: 14),
                    if (_status != null)
                      Expanded(
                        child: Text(
                          _status!,
                          style: TextStyle(
                            color: _update != null
                                ? palette.accentCurrent
                                : palette.fg1,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                  ],
                ),
                if (_update != null && !_launched) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (_installer != null) ...[
                        AppButton.primary(
                          icon: Icons.download,
                          label: _downloading
                              ? 'Downloading…'
                              : 'Download & install',
                          onPressed: _downloading ? null : _downloadAndInstall,
                        ),
                        const SizedBox(width: 10),
                      ],
                      AppButton.secondary(
                        icon: Icons.open_in_new,
                        label: 'Release page',
                        onPressed: _downloading ? null : _openReleasePage,
                      ),
                    ],
                  ),
                ],
                if (_downloading) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _progress == 0 ? null : _progress,
                      minHeight: 4,
                      backgroundColor: palette.bg3,
                    ),
                  ),
                ],
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
      _update = null;
      _installer = null;
      _launched = false;
    });
    final updater = ref.read(updaterProvider);
    try {
      final version = await ref.read(appVersionProvider.future);
      final release = await updater.checkForUpdate(version);
      setState(() {
        _update = release;
        _installer = release == null
            ? null
            : updater.installerAssetFor(release);
        _status = release != null
            ? 'Update available: v${release.version}'
            : 'You are up to date.';
      });
    } on Object catch (e) {
      setState(() => _status = 'Check failed: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _downloadAndInstall() async {
    final asset = _installer;
    if (asset == null) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _status = 'Downloading ${asset.name}…';
    });
    try {
      await ref
          .read(updaterProvider)
          .downloadAndInstall(
            asset,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
      if (!mounted) return;
      setState(() {
        _launched = true;
        _status = 'Installer launched — quit GitOpen to finish updating.';
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Download failed: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _openReleasePage() async {
    await ref.read(updaterProvider).openReleasesPage();
  }
}
