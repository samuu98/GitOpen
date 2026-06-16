# Silent In-App Update & Auto-Relaunch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task (inline; owner wants no subagent dispatch). Steps
> use checkbox (`- [ ]`) syntax.

**Goal:** One-action in-app update with no installer wizard — download → the app
closes itself → the new version installs → the app reopens, on Windows and Linux.

**Architecture:** Pure helpers decide the install command line (`installerLaunchArgs`,
`linuxRelaunchScript`) and are unit-tested. The infrastructure updater shells out
(Windows: silent Inno install, relaunch by the installer; Linux: `pkexec dpkg -i`
then a relaunch-after-exit helper). The UI gates the action behind a confirm dialog
and quits through an injectable `appQuitterProvider`. Spec:
`docs/superpowers/specs/2026-06-16-silent-update-design.md`.

**Tech Stack:** Dart/Flutter, Riverpod, Inno Setup, `dpkg`/`pkexec`, GitHub CD.

---

## Critical context / hazards

1. **Branch `feat/silent-update`** is already created off `main` (at v1.0.1) and the
   spec is committed on it. Stay here.
2. **Single-instance interaction (shipped v1.0.1):** Windows mutex
   `GitOpen-SingleInstance-{A2D8F37C-2D31-4F3D-99A1-7D8B6C7E2A11}`; Linux GApplication
   uniqueness on app-id `com.gitopen.gitopen`. The relaunched new instance must start
   only **after** the old one has exited, or (Linux) it would just re-activate the
   dying primary. Windows: the app quits before the installer's relaunch step (AppMutex
   makes Inno wait). Linux: the relaunch helper polls until our PID is gone, then execs.
3. **Local builds now work** (Dev Mode + VS C++ installed this session) — build Windows
   locally to verify. **Linux can't be built here**; CD `build-linux` is its gate. PR
   CI does NOT compile native code, but this feature is mostly Dart + the `.iss`, so PR
   CI's `flutter analyze`/`flutter test` covers the Dart.
4. **gh account flips** → `gh auth switch --hostname github.com --user zN3utr4l` in the
   same command before push/merge; always `--repo zN3utr4l/GitOpen`; never `--tags`.
5. **Flutter:** `C:\Users\g.chirico\flutter\bin\flutter.bat`. No blanket `dart format`.

---

## File structure

- `lib/application/updates/app_release.dart` — append two pure helpers
  (`installerLaunchArgs`, `linuxRelaunchScript`). Pure, no `dart:io`.
- `test/application/updates/app_release_test.dart` — add helper tests.
- `lib/infrastructure/updates/github_release_updater.dart` — replace `_launch` with
  `_install` (platform branches).
- `lib/ui/services/app_quitter.dart` — new: `AppQuitter` typedef + `appQuitterProvider`
  (closes the window via bitsdojo). Injectable so tests stub it.
- `lib/ui/settings/sections/updates_section.dart` — confirm dialog + quit on success.
- `test/ui/settings/updates_section_test.dart` — new widget test.
- `installer/windows/gitopen.iss` — `[Run]` flag change + `AppMutex`.
- `pubspec.yaml` — `1.0.1+32` → `1.0.2+33`.

---

## Task 1: Pure install-command helpers (TDD)

**Files:**
- Modify: `lib/application/updates/app_release.dart`
- Modify: `test/application/updates/app_release_test.dart`

- [ ] **Step 1: Add failing tests**

Append to `test/application/updates/app_release_test.dart` (inside the top-level
`main()`; if the existing file groups tests, add a new `group`):

```dart
  group('installerLaunchArgs', () {
    test('windows returns Inno silent flags', () {
      expect(
        installerLaunchArgs(InstallerPlatform.windows),
        ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
      );
    });

    test('linux and other have no installer args', () {
      expect(installerLaunchArgs(InstallerPlatform.linux), isEmpty);
      expect(installerLaunchArgs(InstallerPlatform.other), isEmpty);
    });
  });

  group('linuxRelaunchScript', () {
    test('waits for the pid to exit then execs the binary', () {
      final script = linuxRelaunchScript(4321, '/opt/gitopen/gitopen');
      expect(script, contains('kill -0 4321'));
      expect(script, contains('exec "/opt/gitopen/gitopen"'));
    });
  });
```

Ensure the file imports the helpers' library (already imports
`package:gitopen/application/updates/app_release.dart` for the existing tests — verify;
add it if missing).

- [ ] **Step 2: Run, expect failure**

Run: `"C:/Users/g.chirico/flutter/bin/flutter.bat" test test/application/updates/app_release_test.dart`
Expected: FAIL — `installerLaunchArgs`/`linuxRelaunchScript` undefined.

- [ ] **Step 3: Implement the helpers**

Append to `lib/application/updates/app_release.dart`:

```dart
/// Command-line args that make the platform installer run without a wizard.
/// Windows → Inno Setup silent flags. Linux installs via `dpkg` (see the
/// updater), so there are no installer args there.
List<String> installerLaunchArgs(InstallerPlatform platform) {
  return switch (platform) {
    InstallerPlatform.windows => const [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
    ],
    InstallerPlatform.linux || InstallerPlatform.other => const [],
  };
}

/// A `sh -c` script that relaunches GitOpen on Linux once the current process
/// (pid [appPid]) has exited, so the GApplication single-instance name is free
/// before the new instance starts. [exePath] is the freshly installed binary.
String linuxRelaunchScript(int appPid, String exePath) =>
    'while kill -0 $appPid 2>/dev/null; do sleep 0.1; done; exec "$exePath"';
```

- [ ] **Step 4: Run, expect pass**

Run: `"C:/Users/g.chirico/flutter/bin/flutter.bat" test test/application/updates/app_release_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/application/updates/app_release.dart test/application/updates/app_release_test.dart
git commit -m "feat(update): pure helpers for silent install args and linux relaunch"
```

---

## Task 2: Injectable app quitter

**Files:**
- Create: `lib/ui/services/app_quitter.dart`

- [ ] **Step 1: Create the provider**

```dart
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Quits the app. Closing the window exits the process (the native runners are
/// configured to quit on close), which unlocks files for the installer.
typedef AppQuitter = Future<void> Function();

/// Injected so the update flow can quit the app, and tests can stub it.
final appQuitterProvider = Provider<AppQuitter>(
  (ref) => () async => appWindow.close(),
);
```

- [ ] **Step 2: Commit**

```bash
git add lib/ui/services/app_quitter.dart
git commit -m "feat(update): injectable app quitter provider"
```

---

## Task 3: Updater silent/relaunch behaviour

**Files:**
- Modify: `lib/infrastructure/updates/github_release_updater.dart`

- [ ] **Step 1: Replace the `_launch` call in `downloadAndInstall`**

Change the body of `downloadAndInstall` so it calls `_install` instead of `_launch`:

```dart
  Future<void> downloadAndInstall(
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    final file = await _download(asset, onProgress);
    await _install(file);
  }
```

- [ ] **Step 2: Replace the `_launch` method with `_install`**

Replace the entire `_launch` method with:

```dart
  /// Installs [file] without a wizard. Windows: runs the Inno installer silently
  /// (its `[Run]` step relaunches GitOpen). Linux: `pkexec dpkg -i`, then
  /// schedules a relaunch once this process exits. On failure, opens the package
  /// with the system handler and rethrows so the caller keeps the app open.
  Future<void> _install(File file) async {
    if (Platform.isWindows) {
      await Process.start(
        file.path,
        installerLaunchArgs(InstallerPlatform.windows),
        mode: ProcessStartMode.detached,
      );
      return;
    }
    if (Platform.isLinux) {
      ProcessResult result;
      try {
        result = await Process.run('pkexec', ['dpkg', '-i', file.path]);
      } on ProcessException {
        await Process.start(
          'xdg-open',
          [file.path],
          mode: ProcessStartMode.detached,
        );
        throw Exception('pkexec is unavailable; opened the package installer.');
      }
      if (result.exitCode != 0) {
        await Process.start(
          'xdg-open',
          [file.path],
          mode: ProcessStartMode.detached,
        );
        throw Exception(
          'Silent install failed (exit ${result.exitCode}); '
          'opened the package installer instead.',
        );
      }
      final script = linuxRelaunchScript(pid, Platform.resolvedExecutable);
      await Process.start(
        'sh',
        ['-c', script],
        mode: ProcessStartMode.detached,
      );
      return;
    }
    await launchUrl(Uri.file(file.path));
  }
```

(`pid`, `Platform`, `Process`, `ProcessResult`, `ProcessException` all come from
`dart:io`, already imported. `installerLaunchArgs`/`linuxRelaunchScript` come from the
already-imported `app_release.dart`.)

- [ ] **Step 3: Analyze**

Run: `"C:/Users/g.chirico/flutter/bin/flutter.bat" analyze lib/infrastructure/updates/github_release_updater.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/infrastructure/updates/github_release_updater.dart
git commit -m "feat(update): silent install on Windows, pkexec+relaunch on Linux"
```

---

## Task 4: Installer relaunch on silent install

**Files:**
- Modify: `installer/windows/gitopen.iss`

- [ ] **Step 1: Set `AppMutex` in `[Setup]`**

Add this line in the `[Setup]` section (e.g. right after the `SetupIconFile=` line):

```
; Match the app's single-instance mutex so a silent update waits for the running
; instance to close before replacing files.
AppMutex=GitOpen-SingleInstance-{A2D8F37C-2D31-4F3D-99A1-7D8B6C7E2A11}
```

- [ ] **Step 2: Make the post-install launch run on silent installs**

In the `[Run]` section, change the launch entry's flags from
`nowait postinstall skipifsilent` to `nowait postinstall runasoriginaluser` (drop
`skipifsilent` so it relaunches after a silent install too):

```
[Run]
Filename: "{app}\gitopen.exe"; Description: "Launch GitOpen"; \
  Flags: nowait postinstall runasoriginaluser
```

- [ ] **Step 3: Commit**

```bash
git add installer/windows/gitopen.iss
git commit -m "build(win): silent-install relaunch and AppMutex for in-app updates"
```

---

## Task 5: Confirm dialog + quit in the updates UI (widget test)

**Files:**
- Modify: `lib/ui/settings/sections/updates_section.dart`
- Create: `test/ui/settings/updates_section_test.dart`

- [ ] **Step 1: Add the import**

At the top of `updates_section.dart`, add:

```dart
import 'package:gitopen/ui/services/app_quitter.dart';
```

- [ ] **Step 2: Replace `_downloadAndInstall` with the confirm+quit flow**

```dart
  Future<void> _downloadAndInstall() async {
    final asset = _installer;
    if (asset == null) return;
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        title: 'Install update & restart',
        content: Text(
          'GitOpen will download the update, then close and reopen on the new '
          'version. Continue?',
          style: TextStyle(color: palette.fg1, fontSize: 12.5),
        ),
        actions: [
          AppButton.secondary(
            label: 'Cancel',
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          AppButton.primary(
            label: 'Update & restart',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _status = 'Downloading ${asset.name}…';
    });
    try {
      await ref.read(updaterProvider).downloadAndInstall(
        asset,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _launched = true;
        _status = 'Update installed — restarting GitOpen…';
      });
      await ref.read(appQuitterProvider)();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Update failed: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }
```

- [ ] **Step 3: Write the widget test**

Create `test/ui/settings/updates_section_test.dart`:

```dart
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

const _asset =
    ReleaseAsset(name: 'GitOpen-Setup-9.9.9.exe', downloadUrl: 'x', sizeBytes: 1);

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
```

- [ ] **Step 4: Run the widget test**

Run: `"C:/Users/g.chirico/flutter/bin/flutter.bat" test test/ui/settings/updates_section_test.dart`
Expected: PASS (both tests). If `find.text('Download & install')` matches the
`_downloading` label too, it will not — the button label is static until tapped.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings/sections/updates_section.dart test/ui/settings/updates_section_test.dart
git commit -m "feat(update): confirm dialog then auto-quit so the update restarts the app"
```

---

## Task 6: Version bump

**Files:**
- Modify: `pubspec.yaml:4`

- [ ] **Step 1: Bump**

Replace `version: 1.0.1+32` with `version: 1.0.2+33`.

- [ ] **Step 2: Commit**

```bash
git add pubspec.yaml
git commit -m "chore: bump version to 1.0.2"
```

---

## Task 7: Verify locally

**Files:** none

- [ ] **Step 1: Analyze + full test suite**

```bash
cd /d/repos/Personal/GitOpen
"C:/Users/g.chirico/flutter/bin/flutter.bat" analyze
"C:/Users/g.chirico/flutter/bin/flutter.bat" test
```
Expected: `No issues found!` and `All tests passed!`.

- [ ] **Step 2: Build Windows + verify the installer is silent**

```bash
"C:/Users/g.chirico/flutter/bin/flutter.bat" build windows --release
```
Then build the installer (if Inno Setup 6 is present locally) and run it silently to
confirm no wizard appears and the app relaunches:

```bash
ISCC="/c/Program Files (x86)/Inno Setup 6/ISCC.exe"
"$ISCC" //DAppVersion=1.0.2 installer/windows/gitopen.iss
"build/installer/GitOpen-Setup-1.0.2.exe" //VERYSILENT //SUPPRESSMSGBOXES //NORESTART
```
Expected: installs with no wizard window; GitOpen launches afterward. If Inno Setup is
not installed locally, skip the installer build and rely on CD `build-windows` —
**note this in the PR** (no silent caps).

- [ ] **Step 3: No commit** (verification only).

---

## Task 8: Push and open PR

- [ ] **Step 1: Push**

```bash
gh auth switch --hostname github.com --user zN3utr4l && git push -u origin feat/silent-update
```

- [ ] **Step 2: Open PR**

```bash
gh auth switch --hostname github.com --user zN3utr4l && gh pr create --repo zN3utr4l/GitOpen \
  --base main --head feat/silent-update \
  --title "feat: silent in-app update with auto-relaunch" \
  --body "In-app update no longer opens the installer wizard or asks the user to quit manually. After a confirm dialog, GitOpen downloads the update, closes itself, installs silently, and reopens on the new version.

- Windows: installer runs /VERYSILENT; .iss relaunches on silent install + AppMutex waits for the app to close
- Linux: pkexec dpkg -i, then relaunch once the old process exits (fallback to xdg-open on failure)
- UI: confirm dialog + injectable appQuitterProvider; pure installerLaunchArgs/linuxRelaunchScript unit-tested
- pubspec -> 1.0.2+33 (CD publishes v1.0.2)

Spec: docs/superpowers/specs/2026-06-16-silent-update-design.md."
```

- [ ] **Step 3: Wait for checks**

```bash
gh pr checks --repo zN3utr4l/GitOpen --watch
```
Expected: `build-and-test (windows-latest)`, `build-and-test (ubuntu-latest)`,
`version-check` all pass.

---

## Task 9: Confirm merge, then publish v1.0.2

- [ ] **Step 1: STOP — confirm with the owner**

Report PR number, CI status, and local verification. The merge publishes a public
v1.0.2. Only proceed on an explicit go.

- [ ] **Step 2: Merge**

```bash
gh auth switch --hostname github.com --user zN3utr4l && gh pr merge --repo zN3utr4l/GitOpen --merge --delete-branch
```

- [ ] **Step 3: Watch CD + verify the release**

```bash
gh auth switch --hostname github.com --user zN3utr4l && gh run watch --repo zN3utr4l/GitOpen \
  $(gh run list --repo zN3utr4l/GitOpen --workflow cd-release.yml --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status
gh release view v1.0.2 --repo zN3utr4l/GitOpen
```
Expected: CD green; release `GitOpen v1.0.2` with `GitOpen-Setup-1.0.2.exe` +
`gitopen_1.0.2_amd64.deb`.

- [ ] **Step 4: Sync local main**

```bash
git switch main && git fetch origin && git merge --ff-only origin/main
```

---

## Self-review

- **Spec coverage:** Windows silent flags + installer relaunch + AppMutex → Tasks 1,3,4;
  Linux pkexec + relaunch-after-exit + fallback → Tasks 1,3; confirm dialog + self-quit
  → Tasks 2,5; version/publish → Tasks 6,9.
- **Placeholders:** none — full code inline for helpers, updater, provider, UI, tests,
  and `.iss`.
- **Consistency:** `AppMutex` string equals the v1.0.1 single-instance mutex name;
  `installerLaunchArgs(windows)` flags match the `.exe //VERYSILENT //SUPPRESSMSGBOXES
  //NORESTART` invocation; `appQuitterProvider` defined in Task 2 is imported in Task 5
  and overridden in the test; version `1.0.2+33` / `v1.0.2` used consistently.
- **Known non-test:** the updater's `Process` calls and the full restart cycle aren't
  unit-tested (only the pure helpers are); covered by local Windows manual run + CD.
```
