import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings_notifier.dart';
import 'package:gitopen/application/settings/settings_store.dart';
import 'package:gitopen/application/updates/app_release.dart';
import 'package:gitopen/infrastructure/updates/github_release_updater.dart';
import 'package:gitopen/ui/services/app_quitter.dart';
import 'package:gitopen/ui/settings/sections/updates_section.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final class _FakeSettingsStore implements SettingsStore {
  @override
  Future<Map<String, dynamic>> readAll() async => {};
  @override
  Future<void> put(String key, dynamic value) async {}
}

const _asset = ReleaseAsset(
  name: 'GitOpen-Setup-9.9.9.exe',
  downloadUrl: 'x',
  sizeBytes: 1,
);

final class _FakeUpdater extends GitHubReleaseUpdater {
  int installCalls = 0;

  @override
  Future<AppRelease?> checkForUpdate(String currentVersion) async =>
      const AppRelease(version: '9.9.9', assets: [_asset]);

  @override
  ReleaseAsset? installerAssetFor(AppRelease release) => _asset;

  @override
  Future<void> downloadAndInstall(
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    installCalls++;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _FakeUpdater updater,
  List<String> quits,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSettingsProvider
            .overrideWith((ref) => AppSettingsNotifier(_FakeSettingsStore())),
        appVersionProvider.overrideWith((ref) async => '1.0.0'),
        updaterProvider.overrideWithValue(updater),
        appQuitterProvider.overrideWithValue(() async => quits.add('quit')),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: const Scaffold(body: UpdatesSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cancel does not install or quit', (tester) async {
    final updater = _FakeUpdater();
    final quits = <String>[];
    await _pump(tester, updater, quits);

    await tester.tap(find.text('Check now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download & install'));
    await tester.pumpAndSettle();

    expect(find.text('Install update & restart'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(updater.installCalls, 0);
    expect(quits, isEmpty);
  });

  testWidgets('confirm installs then quits', (tester) async {
    final updater = _FakeUpdater();
    final quits = <String>[];
    await _pump(tester, updater, quits);

    await tester.tap(find.text('Check now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download & install'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update & restart'));
    await tester.pumpAndSettle();

    expect(updater.installCalls, 1);
    expect(quits, ['quit']);
  });
}
