# Repository Info Panel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** An info button by the active repo name opens a dialog showing its local path, origin URL, and effective git identity — with copy, open-folder, and open-in-browser actions.

**Architecture:** A pure `remoteWebUrl` normalizes the remote URL for the browser; `repoInfoProvider` combines `repo.path` + the existing remote-URL reader + `GitIdentityService.readEffective`; `RepoInfoDialog` renders three rows; open-folder reuses the existing `RepoLauncher.revealInFiles` (no new port — deviates from the spec's FolderRevealer, which would duplicate it).

**Tech Stack:** Dart/Flutter, Riverpod, flutter_test, url_launcher, flutter/services Clipboard.

## Global Constraints
- `flutter test <path>`; `flutter analyze` clean (≤80 cols, no `<...>` in doc comments unless backticked).
- Origin remote only; read-only; identity is the EFFECTIVE one (local→global).
- Commit messages end with the `Co-Authored-By` trailer.

---

### Task RT1: pure `remoteWebUrl`

**Files:** Create `lib/application/git/remote_web_url.dart`; Test `test/application/git/remote_web_url_test.dart`.

**Produces:** `String? remoteWebUrl(String gitUrl)` — browsable https URL or null.

- [ ] **Step 1 — failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/remote_web_url.dart';

void main() {
  test('normalizes git remote URLs to a browsable https URL', () {
    expect(remoteWebUrl('git@github.com:owner/repo.git'),
        'https://github.com/owner/repo');
    expect(remoteWebUrl('ssh://git@github.com/owner/repo.git'),
        'https://github.com/owner/repo');
    expect(remoteWebUrl('https://github.com/owner/repo.git'),
        'https://github.com/owner/repo');
    expect(remoteWebUrl('https://github.com/owner/repo'),
        'https://github.com/owner/repo');
    expect(remoteWebUrl('/local/path/repo.git'), isNull);
    expect(remoteWebUrl(''), isNull);
  });
}
```

- [ ] **Step 2 — run, expect FAIL** (`remote_web_url.dart` missing).

- [ ] **Step 3 — implement**

```dart
/// Converts a git remote URL to a browsable https URL, or null when it can't
/// produce an http(s) URL. Handles scp-style `git@host:owner/repo(.git)`,
/// `ssh://git@host/owner/repo(.git)`, and `http(s)://…(.git)`.
String? remoteWebUrl(String gitUrl) {
  final url = gitUrl.trim();
  if (url.isEmpty) return null;

  String stripGit(String s) => s.endsWith('.git') ? s.substring(0, s.length - 4) : s;

  // scp-style: git@host:owner/repo.git
  final scp = RegExp(r'^[^@/]+@([^:/]+):(.+)$').firstMatch(url);
  if (scp != null && !url.contains('://')) {
    return 'https://${scp.group(1)}/${stripGit(scp.group(2)!)}';
  }
  // ssh://[user@]host/owner/repo.git  or  git://host/...
  final ssh = RegExp(r'^(?:ssh|git)://(?:[^@/]+@)?([^/]+)/(.+)$').firstMatch(url);
  if (ssh != null) {
    return 'https://${ssh.group(1)}/${stripGit(ssh.group(2)!)}';
  }
  // http(s)://…
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return stripGit(url);
  }
  return null;
}
```

- [ ] **Step 4 — run, expect PASS.**

- [ ] **Step 5 — commit**
```bash
git add lib/application/git/remote_web_url.dart test/application/git/remote_web_url_test.dart
git commit -m "feat(git): pure remoteWebUrl normalizer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task RT2: `repoInfoProvider`

**Files:** Modify `lib/application/providers.dart`; Test `test/application/repo_info_provider_test.dart`.

**Consumes:** `remoteUrlReaderProvider`, `gitIdentityServiceProvider` (both exist).
**Produces:** `repoInfoProvider(RepoLocation)` → `Future<({String path, String? originUrl, String? userName, String? userEmail})>`.

- [ ] **Step 1 — failing test** (fixture repo with origin + local identity)

```dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import '../_helpers/repo_fixture.dart';

void main() {
  test('reports path, origin url and effective identity', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      await Process.run('git', ['remote', 'add', 'origin',
          'https://github.com/o/r.git'], workingDirectory: f.path);
      await Process.run('git', ['config', 'user.name', 'Tester'],
          workingDirectory: f.path);
      await Process.run('git', ['config', 'user.email', 't@e.com'],
          workingDirectory: f.path);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final repo = RepoLocation(const RepoId('r'), f.path, 'r');
      final info = await container.read(repoInfoProvider(repo).future);
      expect(info.path, f.path);
      expect(info.originUrl, 'https://github.com/o/r.git');
      expect(info.userName, 'Tester');
      expect(info.userEmail, 't@e.com');
    } finally {
      await f.dispose();
    }
  });
}
```

- [ ] **Step 2 — run, expect FAIL** (`repoInfoProvider` undefined).

- [ ] **Step 3 — implement** (add near the other repo providers)

```dart
typedef RepoInfo = ({
  String path,
  String? originUrl,
  String? userName,
  String? userEmail,
});

final repoInfoProvider =
    FutureProvider.family<RepoInfo, RepoLocation>((ref, repo) async {
  final originUrl =
      await ref.watch(remoteUrlReaderProvider).remoteUrl(repo, 'origin');
  final id = await ref.watch(gitIdentityServiceProvider).readEffective(repo);
  return (
    path: repo.path,
    originUrl: originUrl,
    userName: id.name,
    userEmail: id.email,
  );
});
```

- [ ] **Step 4 — run, expect PASS.**

- [ ] **Step 5 — commit**
```bash
git add lib/application/providers.dart test/application/repo_info_provider_test.dart
git commit -m "feat(git): repoInfoProvider (path + origin + identity)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task RT3: `RepoInfoDialog` + title-bar info button

**Files:** Create `lib/ui/dialogs/repo_info_dialog.dart`; Modify `lib/main.dart` (`_TitleBar`); Test `test/ui/dialogs/repo_info_dialog_test.dart`.

**Consumes:** `repoInfoProvider` (RT2), `remoteWebUrl` (RT1), `repoLauncherProvider.revealInFiles`, `AppDialog`/`AppButton`/`AppPalette`, `Clipboard`, `launchUrl`.

- [ ] **Step 1 — failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/repo_info_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  testWidgets('shows path, origin and identity; copy puts path on clipboard',
      (tester) async {
    const repo = RepoLocation(RepoId('r'), r'C:\repos\demo', 'demo');
    final container = ProviderContainer(overrides: [
      repoInfoProvider(repo).overrideWith((ref) async => (
            path: r'C:\repos\demo',
            originUrl: 'https://github.com/o/r.git',
            userName: 'Tester',
            userEmail: 't@e.com',
          )),
    ]);
    addTearDown(container.dispose);

    final copied = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied.add(call);
        return null;
      },
    );

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => RepoInfoDialog.show(context, repo: repo),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text(r'C:\repos\demo'), findsOneWidget);
    expect(find.text('https://github.com/o/r.git'), findsOneWidget);
    expect(find.text('Tester <t@e.com>'), findsOneWidget);

    // Tap the first copy button (path).
    await tester.tap(find.byIcon(Icons.copy_outlined).first);
    await tester.pump();
    expect(copied.single.arguments['text'], r'C:\repos\demo');
  });
}
```

- [ ] **Step 2 — run, expect FAIL** (dialog missing).

- [ ] **Step 3 — implement the dialog**

Create `lib/ui/dialogs/repo_info_dialog.dart`: a `ConsumerWidget` `AppDialog` titled "Repository" that watches `repoInfoProvider(repo)`. While loading show a small spinner; on data render three `_InfoRow`s:
- Path row: label "Local path", value `info.path`, actions: copy(`info.path`) + open-folder (`ref.read(repoLauncherProvider).revealInFiles(repo)` wrapped in try/catch → snackbar on failure).
- Origin row: label "Remote (origin)", value `info.originUrl ?? 'No remote'`; copy shown only when `originUrl != null`; open-browser shown only when `remoteWebUrl(info.originUrl!) != null` → `launchUrl(Uri.parse(...), mode: LaunchMode.externalApplication)`.
- Identity row: label "Git user", value `(info.userName == null && info.userEmail == null) ? 'Not set' : '${info.userName ?? '?'} <${info.userEmail ?? '?'}>'`; copy of that string when set.

`_InfoRow({required label, required value, required actions})` — a `Row` with a fixed-width label, an `Expanded` SelectableText/Text(value, monospace, ellipsis), and the trailing action `IconButton`s (`Icons.copy_outlined`, `Icons.folder_open`, `Icons.open_in_new`), each `splashRadius:16`, compact. Copy helper: `Clipboard.setData(ClipboardData(text: v))` + a "Copied" snackbar via `ScaffoldMessenger`.

`RepoInfoDialog.show(BuildContext, {required RepoLocation repo})` → `showDialog`.

- [ ] **Step 4 — run, expect PASS.**

- [ ] **Step 5 — wire the title-bar button**

In `main.dart` `_TitleBar.build`, the Row has `const RepoSelector()`. Wrap so that when a repo is active an info button follows it. `_TitleBar` is a `ConsumerWidget`? It's `ConsumerWidget` (it uses `ref`). Add:
```dart
            const RepoSelector(),
            Consumer(
              builder: (context, ref, _) {
                final workspaces = ref.watch(workspaceManagerProvider);
                final activeId = ref.watch(activeWorkspaceIdProvider);
                final active = activeId == null
                    ? null
                    : workspaces.firstWhereOrNull((w) => w.location.id == activeId);
                if (active == null) return const SizedBox.shrink();
                return IconButton(
                  icon: Icon(Icons.info_outline, size: 15, color: palette.fg2),
                  tooltip: 'Repository info',
                  onPressed: () =>
                      RepoInfoDialog.show(context, repo: active.location),
                );
              },
            ),
            const SizedBox(width: 8),
            const GitToolbar(),
```
Add imports: `package:collection/collection.dart` (firstWhereOrNull — likely already used in main), `repo_info_dialog.dart`, `active_workspace_provider.dart` + `workspaceManagerProvider` (providers — already imported in main).

- [ ] **Step 6 — analyze + full suite**

Run: `flutter analyze`  → no issues.
Run: `flutter test`  → PASS (a real-git submodule test may flake under parallel load; re-run alone to confirm).

- [ ] **Step 7 — manual smoke**

`flutter run -d windows`, open a repo → click the ℹ button → see path/origin/identity; copy buttons copy; open-folder reveals the directory; open-in-browser opens the repo page.

- [ ] **Step 8 — commit**
```bash
git add lib/ui/dialogs/repo_info_dialog.dart lib/main.dart test/ui/dialogs/repo_info_dialog_test.dart
git commit -m "feat(ui): repository info panel (path, origin, git identity)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

- Spec coverage: path/origin/identity rows (RT3), copy/open-folder/open-browser (RT3), remoteWebUrl (RT1), data (RT2). ✓
- **Deviation:** open-folder reuses the existing `RepoLauncher.revealInFiles` instead of a new `FolderRevealer` port (DRY — the launcher already does explorer/open/xdg-open). Spec's FolderRevealer dropped.
- Placeholder scan: dialog body described prose-level but with exact provider/row/action wiring + full code for RT1/RT2 and the title-bar block; RT3's widget is standard `AppDialog`+`Row` composition.
- Type consistency: `RepoInfo` record `({path, originUrl, userName, userEmail})` used in RT2 + RT3; `remoteWebUrl` in RT1 + RT3.
