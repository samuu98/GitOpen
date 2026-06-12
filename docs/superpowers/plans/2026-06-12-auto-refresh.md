# Auto-refresh on External Repository Changes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GitOpen refreshes a repo's UI automatically when another client (git CLI, other GUIs) changes it on disk.

**Architecture:** A per-open-repo filesystem watcher (`watcher` package) on the repo root; a pure filter keeps only events that imply git state changed; a trailing debounce coalesces bursts; the callback bumps the existing `repoRevisionProvider` via `refreshRepo`, which all repo-scoped read providers already watch. Watchers are reconciled in `Shell` exactly like `_reconcileAutoFetchTimer`. A new `autoRefreshEnabled` setting (default on) gates the feature.

**Tech Stack:** Flutter/Dart, Riverpod, `watcher` ^1.1.0, `fake_async` (ships with flutter_test) for debounce tests.

Spec: `docs/superpowers/specs/2026-06-12-auto-refresh-design.md`

**Test note (Windows):** run tests with `$env:NO_PROXY = "127.0.0.1,localhost"` set first, or the test harness 502s on the loopback websocket.

---

### Task 1: Event filter `isRelevantRepoEvent`

**Files:**
- Modify: `pubspec.yaml` (add `watcher: ^1.1.0` under Utilities)
- Create: `lib/application/auto_refresh/repo_change_watcher.dart`
- Test: `test/application/auto_refresh/repo_change_filter_test.dart`

- [ ] **Step 1: Add dependency**

In `pubspec.yaml` under `# Utilities` add:

```yaml
  watcher: ^1.1.0
```

Run: `flutter pub get` — expect success.

- [ ] **Step 2: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auto_refresh/repo_change_watcher.dart';

void main() {
  const root = r'C:\repos\demo';

  group('isRelevantRepoEvent', () {
    test('worktree file changes are relevant', () {
      expect(isRelevantRepoEvent(root, r'C:\repos\demo\lib\main.dart'), isTrue);
    });

    test('.git internals are irrelevant by default', () {
      expect(isRelevantRepoEvent(root, r'C:\repos\demo\.git\objects\ab\cdef'), isFalse);
      expect(isRelevantRepoEvent(root, r'C:\repos\demo\.git\logs\HEAD'), isFalse);
      expect(isRelevantRepoEvent(root, r'C:\repos\demo\.git\FETCH_HEAD'), isFalse);
      expect(isRelevantRepoEvent(root, r'C:\repos\demo\.git'), isFalse);
    });

    test('git state files are relevant', () {
      for (final f in ['HEAD', 'ORIG_HEAD', 'MERGE_HEAD', 'CHERRY_PICK_HEAD',
                       'REVERT_HEAD', 'index', 'packed-refs']) {
        expect(isRelevantRepoEvent(root, 'C:\\repos\\demo\\.git\\$f'), isTrue,
            reason: f);
      }
    });

    test('refs are relevant, their lock files are not', () {
      expect(isRelevantRepoEvent(root, r'C:\repos\demo\.git\refs\heads\main'), isTrue);
      expect(isRelevantRepoEvent(root, r'C:\repos\demo\.git\refs\remotes\origin\main'), isTrue);
      expect(isRelevantRepoEvent(root, r'C:\repos\demo\.git\refs\heads\main.lock'), isFalse);
      expect(isRelevantRepoEvent(root, r'C:\repos\demo\.git\index.lock'), isFalse);
    });

    test('posix separators work too', () {
      expect(isRelevantRepoEvent('/home/u/demo', '/home/u/demo/.git/refs/heads/main'), isTrue);
      expect(isRelevantRepoEvent('/home/u/demo', '/home/u/demo/.git/objects/aa/bb'), isFalse);
      expect(isRelevantRepoEvent('/home/u/demo', '/home/u/demo/src/app.dart'), isTrue);
    });
  });
}
```

- [ ] **Step 3: Run test, verify it fails**

Run: `flutter test test/application/auto_refresh/repo_change_filter_test.dart`
Expected: FAIL — `isRelevantRepoEvent` undefined.

- [ ] **Step 4: Implement the filter**

`lib/application/auto_refresh/repo_change_watcher.dart`:

```dart
import 'package:path/path.dart' as p;

/// Git state files inside `.git/` whose change means "repo state moved".
const _gitStateFiles = {
  'HEAD', 'ORIG_HEAD', 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD',
  'index', 'packed-refs',
};

/// Whether a filesystem event at [eventPath] implies the repo at [repoRoot]
/// changed in a way the UI should reflect.
///
/// Working-tree paths always count (they drive the working-copy panel).
/// Inside `.git/` only ref updates and the well-known state files count;
/// object/pack writes, reflogs and `*.lock` churn are noise.
bool isRelevantRepoEvent(String repoRoot, String eventPath) {
  final rel = p.relative(eventPath, from: repoRoot).replaceAll('\\', '/');
  if (rel != '.git' && !rel.startsWith('.git/')) return true;
  if (rel == '.git') return false;
  final inner = rel.substring('.git/'.length);
  if (inner.endsWith('.lock')) return false;
  return _gitStateFiles.contains(inner) || inner.startsWith('refs/');
}
```

- [ ] **Step 5: Run test, verify it passes**

Run: `flutter test test/application/auto_refresh/repo_change_filter_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/application/auto_refresh/repo_change_watcher.dart test/application/auto_refresh/repo_change_filter_test.dart
git commit -m "feat(auto-refresh): event filter for external repo changes"
```

---

### Task 2: `RepoChangeWatcher` with debounce

**Files:**
- Modify: `lib/application/auto_refresh/repo_change_watcher.dart`
- Test: `test/application/auto_refresh/repo_change_watcher_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auto_refresh/repo_change_watcher.dart';
import 'package:watcher/watcher.dart';

void main() {
  const root = '/repo';
  WatchEvent ev(String path) => WatchEvent(ChangeType.MODIFY, path);

  test('coalesces a burst of relevant events into one callback', () {
    fakeAsync((async) {
      final controller = StreamController<WatchEvent>(sync: true);
      var calls = 0;
      final w = RepoChangeWatcher(
        repoRoot: root,
        onChanged: () => calls++,
        watchStream: (_) => controller.stream,
      );
      controller.add(ev('$root/.git/refs/heads/main'));
      controller.add(ev('$root/.git/refs/remotes/origin/main'));
      controller.add(ev('$root/.git/HEAD'));
      async.elapse(const Duration(milliseconds: 599));
      expect(calls, 0, reason: 'still inside debounce window');
      async.elapse(const Duration(milliseconds: 1));
      expect(calls, 1);
      w.dispose();
    });
  });

  test('irrelevant events never fire the callback', () {
    fakeAsync((async) {
      final controller = StreamController<WatchEvent>(sync: true);
      var calls = 0;
      final w = RepoChangeWatcher(
        repoRoot: root,
        onChanged: () => calls++,
        watchStream: (_) => controller.stream,
      );
      controller.add(ev('$root/.git/objects/aa/bb'));
      controller.add(ev('$root/.git/index.lock'));
      async.elapse(const Duration(seconds: 5));
      expect(calls, 0);
      w.dispose();
    });
  });

  test('dispose cancels a pending debounce', () {
    fakeAsync((async) {
      final controller = StreamController<WatchEvent>(sync: true);
      var calls = 0;
      final w = RepoChangeWatcher(
        repoRoot: root,
        onChanged: () => calls++,
        watchStream: (_) => controller.stream,
      );
      controller.add(ev('$root/file.txt'));
      w.dispose();
      async.elapse(const Duration(seconds: 5));
      expect(calls, 0);
    });
  });

  test('stream error stops the watcher without throwing', () {
    fakeAsync((async) {
      final controller = StreamController<WatchEvent>(sync: true);
      var calls = 0;
      final w = RepoChangeWatcher(
        repoRoot: root,
        onChanged: () => calls++,
        watchStream: (_) => controller.stream,
      );
      controller.addError(const FileSystemException('gone'));
      controller.add(ev('$root/file.txt'));
      async.elapse(const Duration(seconds: 5));
      expect(calls, 0);
      expect(w.isActive, isFalse);
      w.dispose();
    });
  });
}
```

Add `import 'dart:io' show FileSystemException;` if the analyzer asks for it.

- [ ] **Step 2: Run tests, verify they fail**

Run: `flutter test test/application/auto_refresh/repo_change_watcher_test.dart`
Expected: FAIL — `RepoChangeWatcher` undefined.

- [ ] **Step 3: Implement the watcher**

Append to `lib/application/auto_refresh/repo_change_watcher.dart`:

```dart
import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../../infrastructure/logging/app_logger.dart';
```

(merge imports at the top of the file) and:

```dart
typedef WatchStreamFactory = Stream<WatchEvent> Function(String path);

Stream<WatchEvent> _defaultWatchStream(String path) =>
    DirectoryWatcher(path).events;

/// Watches one repository root and invokes [onChanged] (debounced) when the
/// repo changes on disk in a way the UI should reflect — i.e. when
/// [isRelevantRepoEvent] accepts the event.
///
/// On a stream error (deleted directory, unreachable network drive) the
/// watcher logs and stops; the owner's next reconcile recreates it if the
/// repo is still open.
final class RepoChangeWatcher {
  RepoChangeWatcher({
    required this.repoRoot,
    required this.onChanged,
    WatchStreamFactory? watchStream,
    this.debounce = const Duration(milliseconds: 600),
  }) {
    _sub = (watchStream ?? _defaultWatchStream)(repoRoot).listen(
      _onEvent,
      onError: (Object e) {
        appLog.w('Repo watcher stopped for $repoRoot: $e');
        dispose();
      },
    );
  }

  final String repoRoot;
  final void Function() onChanged;
  final Duration debounce;

  StreamSubscription<WatchEvent>? _sub;
  Timer? _debounceTimer;
  bool _disposed = false;

  /// False once disposed or stopped by a stream error.
  bool get isActive => !_disposed;

  void _onEvent(WatchEvent event) {
    if (_disposed || !isRelevantRepoEvent(repoRoot, event.path)) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      if (!_disposed) onChanged();
    });
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _sub?.cancel();
    _sub = null;
  }
}
```

- [ ] **Step 4: Run tests, verify they pass**

Run: `flutter test test/application/auto_refresh/`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/application/auto_refresh/repo_change_watcher.dart test/application/auto_refresh/repo_change_watcher_test.dart
git commit -m "feat(auto-refresh): debounced per-repo filesystem watcher"
```

---

### Task 3: `autoRefreshEnabled` setting

**Files:**
- Modify: `lib/application/settings/app_settings.dart`
- Modify: `lib/application/settings/app_settings_notifier.dart`
- Test: `test/application/settings/auto_refresh_setting_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/settings/app_settings.dart';

void main() {
  test('autoRefreshEnabled defaults to true', () {
    expect(const AppSettingsState().autoRefreshEnabled, isTrue);
  });

  test('copyWith toggles autoRefreshEnabled and affects equality', () {
    const a = AppSettingsState();
    final b = a.copyWith(autoRefreshEnabled: false);
    expect(b.autoRefreshEnabled, isFalse);
    expect(a == b, isFalse);
  });
}
```

- [ ] **Step 2: Run test, verify it fails**

Run: `flutter test test/application/settings/auto_refresh_setting_test.dart`
Expected: FAIL — no such getter.

- [ ] **Step 3: Add the field**

In `app_settings.dart`, after `autoFetchIntervalMinutes` (field, constructor default, `copyWith` param + body, `props`):

```dart
  /// Refresh a repo's UI automatically when it changes on disk (commits,
  /// branch moves, staging done by other clients). On by default.
  final bool autoRefreshEnabled;
```

Constructor: `this.autoRefreshEnabled = true,`
`copyWith` parameter: `bool? autoRefreshEnabled,`
`copyWith` body: `autoRefreshEnabled: autoRefreshEnabled ?? this.autoRefreshEnabled,`
`props`: add `autoRefreshEnabled` after `autoFetchIntervalMinutes`.

In `app_settings_notifier.dart`:
- `_load()`: `autoRefreshEnabled: (all['auto_refresh_enabled'] as bool?) ?? true,`
- New setter next to `setAutoFetchEnabled`:

```dart
  Future<void> setAutoRefreshEnabled(bool v) async {
    state = state.copyWith(autoRefreshEnabled: v);
    await _repo.put('auto_refresh_enabled', v);
  }
```

- [ ] **Step 4: Run test, verify it passes**

Run: `flutter test test/application/settings/auto_refresh_setting_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/application/settings/app_settings.dart lib/application/settings/app_settings_notifier.dart test/application/settings/auto_refresh_setting_test.dart
git commit -m "feat(auto-refresh): autoRefreshEnabled setting (default on)"
```

---

### Task 4: Settings UI toggle

**Files:**
- Modify: `lib/ui/settings/sections/general_section.dart` (after the "Fetch interval" row, ~line 188)

- [ ] **Step 1: Add the row**

The "Fetch interval" `SettingsRow` currently has `divider: false` (last row). Move `divider: false` to the new row and append after the fetch-interval row:

```dart
                SettingsRow(
                  label: 'Auto-refresh',
                  description:
                      'Refresh automatically when the repository changes on disk '
                      '(e.g. commits made from another client).',
                  divider: false,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Switch(
                      value: s.autoRefreshEnabled,
                      onChanged: notifier.setAutoRefreshEnabled,
                    ),
                  ),
                ),
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/ui/settings/sections/general_section.dart`
Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add lib/ui/settings/sections/general_section.dart
git commit -m "feat(auto-refresh): settings toggle in General section"
```

---

### Task 5: Shell wiring

**Files:**
- Modify: `lib/main.dart` (`_ShellState`, around lines 196–285)

- [ ] **Step 1: Wire the reconcile**

Imports (top of `main.dart`): add

```dart
import 'application/auto_refresh/repo_change_watcher.dart';
```

(`RepoLocation`, `Workspace`, `refreshRepo` are already imported there.)

In `_ShellState`, next to `_autoFetchTimer`:

```dart
  /// One filesystem watcher per open repo (see [_reconcileRepoWatchers]).
  final Map<RepoLocation, RepoChangeWatcher> _repoWatchers = {};
```

In `dispose()`, before `super.dispose()`:

```dart
    for (final w in _repoWatchers.values) {
      w.dispose();
    }
    _repoWatchers.clear();
```

New method next to `_reconcileAutoFetchTimer`:

```dart
  /// Keeps one [RepoChangeWatcher] per open repo, matching the current tabs
  /// and the auto-refresh setting. Idempotent — safe to call on every build.
  /// Watchers killed by stream errors are also pruned (and recreated) here.
  void _reconcileRepoWatchers(List<Workspace> workspaces, bool enabled) {
    final wanted = <RepoLocation>{
      if (enabled) ...workspaces.map((w) => w.location),
    };
    _repoWatchers.removeWhere((loc, watcher) {
      if (wanted.contains(loc) && watcher.isActive) return false;
      watcher.dispose();
      return true;
    });
    for (final loc in wanted) {
      _repoWatchers.putIfAbsent(
        loc,
        () => RepoChangeWatcher(
          repoRoot: loc.path,
          onChanged: () {
            if (mounted) refreshRepo(ref, loc);
          },
        ),
      );
    }
  }
```

In `build()`, right after `_reconcileAutoFetchTimer(...)`:

```dart
    final autoRefresh =
        ref.watch(appSettingsProvider.select((s) => s.autoRefreshEnabled));
    _reconcileRepoWatchers(workspaces, autoRefresh);
```

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add lib/main.dart
git commit -m "feat(auto-refresh): reconcile per-repo watchers in Shell"
```

---

### Task 6: Full verification

- [ ] **Step 1: Full test suite**

Run (PowerShell): `$env:NO_PROXY = "127.0.0.1,localhost"; flutter test`
Expected: all tests PASS.

- [ ] **Step 2: Analyzer**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 3: Manual smoke test (best effort)**

Launch `flutter run -d windows` against a scratch repo, commit from a separate
terminal (`git commit --allow-empty -m x`), confirm the graph updates within
~1 s without pressing F5. Skip if no interactive session is available — the
unit tests cover the logic.

- [ ] **Step 4: Update README Slice 3 list**

Add to the Slice 3 bullet list in `README.md`:

```markdown
- **Auto-refresh**: filesystem watcher per open repo — commits/branch changes made by other clients appear automatically (toggle in Settings → General)
```

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: auto-refresh in README feature list"
```
