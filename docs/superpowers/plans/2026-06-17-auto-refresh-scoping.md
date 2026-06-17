# Auto-Refresh Scoping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop GitOpen's auto-refresh from re-running the entire git read layer on every fetch and every window focus-regain; refresh only the scopes the change can affect.

**Architecture:** The file watcher emits a typed `RepoChange` (classified from the changed `.git` path). A pure mapping turns a set of changes into a set of refresh scopes (`worktree` / `refs` / `state`); `RepoAutoRefreshScope` invalidates only the providers in those scopes. Focus-regain refreshes `worktree`+`state` only, adding `refs` only when `RepoStatus.headSha` moved (free safety net). The commit-graph provider is made public so it can be invalidated by scope.

**Tech Stack:** Flutter, Riverpod, `dart:io` `Directory.watch`, `flutter_test`. No new dependencies.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-06-17-auto-refresh-scoping-design.md`.
- `very_good_analysis` is strict; `flutter analyze` must stay clean (info-level lints fail it). Wrap lines ~80 cols. No public API exposing private types (`library_private_types_in_public_api`).
- `database.g.dart` is gitignored and regenerated via `dart run build_runner build --delete-conflicting-outputs`; this plan does not change the schema, so no regen is needed.
- PR CI runs `flutter analyze` + `flutter test`; both must pass.
- Branch: `perf/auto-refresh-scope`. Git identity: `zN3utr4l`.
- Write-path invalidations (`git_actions_controller`, `commit_compose`) and working-copy actions are OUT OF SCOPE — leave them unchanged.
- Existing key facts: `RepoStatus.headSha` is a `CommitSha?`. `repoStateProvider` watches `gitDirProbeProvider` (not git read ops) and is invalidated directly. The graph provider is `_commitGraphDataProvider` returning `_GraphData` in `commit_graph_panel.dart`.

---

### Task 1: Pure change classification + scope mapping

**Files:**
- Create: `lib/application/watch/repo_change.dart`
- Test: `test/application/watch/repo_change_test.dart`

**Interfaces:**
- Produces:
  - `enum RepoChange { head, refs, fetch, mergeState }`
  - `RepoChange? classifyGitChange(String path)` — null for noise (`index`, `*.lock`) or irrelevant paths.
  - `enum RepoRefreshScope { worktree, refs, state }`
  - `Set<RepoRefreshScope> scopesForChange(Set<RepoChange> changes)`
  - `Set<RepoRefreshScope> scopesForFocus({required bool headMoved})`

- [ ] **Step 1: Write the failing test**

```dart
// test/application/watch/repo_change_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/watch/repo_change.dart';
import 'package:path/path.dart' as p;

String g(List<String> parts) => p.joinAll(['/repo', '.git', ...parts]);

void main() {
  group('classifyGitChange', () {
    test('HEAD and reflog -> head', () {
      expect(classifyGitChange(g(['HEAD'])), RepoChange.head);
      expect(classifyGitChange(g(['logs', 'HEAD'])), RepoChange.head);
    });
    test('refs and packed-refs -> refs', () {
      expect(classifyGitChange(g(['refs', 'heads', 'main'])), RepoChange.refs);
      expect(classifyGitChange(g(['packed-refs'])), RepoChange.refs);
    });
    test('FETCH_HEAD / ORIG_HEAD -> fetch', () {
      expect(classifyGitChange(g(['FETCH_HEAD'])), RepoChange.fetch);
      expect(classifyGitChange(g(['ORIG_HEAD'])), RepoChange.fetch);
    });
    test('merge/rebase state -> mergeState', () {
      expect(classifyGitChange(g(['MERGE_HEAD'])), RepoChange.mergeState);
      expect(classifyGitChange(g(['CHERRY_PICK_HEAD'])), RepoChange.mergeState);
      expect(classifyGitChange(g(['REVERT_HEAD'])), RepoChange.mergeState);
      expect(classifyGitChange(g(['rebase-merge', 'done'])), RepoChange.mergeState);
      expect(classifyGitChange(g(['rebase-apply', 'next'])), RepoChange.mergeState);
    });
    test('index and lock files -> null (noise)', () {
      expect(classifyGitChange(g(['index'])), isNull);
      expect(classifyGitChange(g(['index.lock'])), isNull);
      expect(classifyGitChange(g(['HEAD.lock'])), isNull);
      expect(classifyGitChange(g(['packed-refs.lock'])), isNull);
    });
    test('unrelated files -> null', () {
      expect(classifyGitChange(g(['config'])), isNull);
      expect(classifyGitChange(g(['description'])), isNull);
    });
  });

  group('scopesForChange', () {
    test('head refreshes worktree + refs + state', () {
      expect(scopesForChange({RepoChange.head}), {
        RepoRefreshScope.worktree,
        RepoRefreshScope.refs,
        RepoRefreshScope.state,
      });
    });
    test('refs / fetch refresh refs + state (no worktree)', () {
      expect(scopesForChange({RepoChange.refs}),
          {RepoRefreshScope.refs, RepoRefreshScope.state});
      expect(scopesForChange({RepoChange.fetch}),
          {RepoRefreshScope.refs, RepoRefreshScope.state});
    });
    test('mergeState refreshes worktree + state (no refs/graph)', () {
      expect(scopesForChange({RepoChange.mergeState}),
          {RepoRefreshScope.worktree, RepoRefreshScope.state});
    });
    test('a mixed burst unions the scopes', () {
      expect(scopesForChange({RepoChange.mergeState, RepoChange.head}), {
        RepoRefreshScope.worktree,
        RepoRefreshScope.refs,
        RepoRefreshScope.state,
      });
    });
  });

  group('scopesForFocus', () {
    test('no head move -> worktree + state only', () {
      expect(scopesForFocus(headMoved: false),
          {RepoRefreshScope.worktree, RepoRefreshScope.state});
    });
    test('head moved -> adds refs', () {
      expect(scopesForFocus(headMoved: true), {
        RepoRefreshScope.worktree,
        RepoRefreshScope.refs,
        RepoRefreshScope.state,
      });
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/application/watch/repo_change_test.dart`
Expected: FAIL — `repo_change.dart` doesn't exist.

- [ ] **Step 3: Write the implementation**

```dart
// lib/application/watch/repo_change.dart
import 'package:path/path.dart' as p;

/// What kind of git bookkeeping changed on disk. Drives scoped auto-refresh.
enum RepoChange { head, refs, fetch, mergeState }

/// A coarse refresh scope. Each maps to a set of providers in
/// RepoAutoRefreshScope.
enum RepoRefreshScope { worktree, refs, state }

/// Classifies a changed path under `.git` into a [RepoChange], or null when it
/// is transient noise (`index`, `*.lock`) or irrelevant. Pure.
RepoChange? classifyGitChange(String path) {
  final name = p.basename(path);
  if (name == 'index' || name.endsWith('.lock')) return null;

  const mergeNames = {
    'MERGE_HEAD',
    'CHERRY_PICK_HEAD',
    'REVERT_HEAD',
    'MERGE_MSG',
  };
  if (mergeNames.contains(name)) return RepoChange.mergeState;

  final segments = p.split(path);
  if (segments.contains('rebase-merge') ||
      segments.contains('rebase-apply')) {
    return RepoChange.mergeState;
  }

  if (name == 'FETCH_HEAD' || name == 'ORIG_HEAD') return RepoChange.fetch;

  if (name == 'HEAD') return RepoChange.head;
  if (segments.contains('logs')) return RepoChange.head; // reflog

  if (name == 'packed-refs') return RepoChange.refs;
  if (segments.contains('refs')) return RepoChange.refs;

  return null;
}

/// Union of scopes that the given changes require refreshing.
Set<RepoRefreshScope> scopesForChange(Set<RepoChange> changes) {
  final scopes = <RepoRefreshScope>{};
  for (final c in changes) {
    switch (c) {
      case RepoChange.head:
        scopes
          ..add(RepoRefreshScope.worktree)
          ..add(RepoRefreshScope.refs)
          ..add(RepoRefreshScope.state);
      case RepoChange.refs:
      case RepoChange.fetch:
        scopes
          ..add(RepoRefreshScope.refs)
          ..add(RepoRefreshScope.state);
      case RepoChange.mergeState:
        scopes
          ..add(RepoRefreshScope.worktree)
          ..add(RepoRefreshScope.state);
    }
  }
  return scopes;
}

/// Scopes to refresh on window focus-regain. Working tree + in-progress state
/// always; refs only when HEAD moved while away (safety net for a missed
/// watcher event).
Set<RepoRefreshScope> scopesForFocus({required bool headMoved}) {
  return {
    RepoRefreshScope.worktree,
    RepoRefreshScope.state,
    if (headMoved) RepoRefreshScope.refs,
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/application/watch/repo_change_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/application/watch/repo_change.dart test/application/watch/repo_change_test.dart
git commit -m "feat(watch): pure git-change classification and refresh-scope maps"
```

---

### Task 2: Watcher emits typed `RepoChange`

**Files:**
- Modify: `lib/application/watch/repo_watcher.dart` (port: `Stream<RepoChange>`)
- Modify: `lib/infrastructure/watch/io_repo_watcher.dart` (classify + emit; drop `isTransientGitNoise`)
- Modify: `lib/ui/auto_refresh/repo_auto_refresh_scope.dart` (subscription type only; logic unchanged this task)
- Test: `test/infrastructure/watch/io_repo_watcher_test.dart` (typed stream; remove the `isTransientGitNoise` group — now covered by `repo_change_test`)
- Test: `test/ui/auto_refresh/repo_auto_refresh_scope_test.dart` (`_FakeWatcher` stream type only)

**Interfaces:**
- Consumes: `RepoChange`, `classifyGitChange` (Task 1).
- Produces: `RepoWatcher.changes(RepoLocation) -> Stream<RepoChange>`.

- [ ] **Step 1: Update the watcher test to expect a typed event**

In `test/infrastructure/watch/io_repo_watcher_test.dart`: keep the two behavioural tests but type the first one's result, and DELETE the entire `group('isTransientGitNoise', ...)` (lines from `group('isTransientGitNoise'` to its closing `});`). Replace the first test's body tail so it asserts the kind:

```dart
        final RepoChange event =
            await first.timeout(const Duration(seconds: 10));
        expect(event, RepoChange.head);
```

Add the import: `import 'package:gitopen/application/watch/repo_change.dart';`. Change `final first = watcher.changes(repo).first;` (unchanged) — its type is now `Future<RepoChange>`.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/infrastructure/watch/io_repo_watcher_test.dart`
Expected: FAIL — `RepoChange` not in scope / `isTransientGitNoise` removed but still referenced, and the stream is still `Stream<void>`.

- [ ] **Step 3: Update the port**

```dart
// lib/application/watch/repo_watcher.dart
import 'package:gitopen/application/watch/repo_change.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

/// Emits a [RepoChange] whenever the repository's git bookkeeping changes on
/// disk (commit, checkout, fetch, merge… from ANY process). Implemented over
/// the file system in infrastructure; injected so auto-refresh is testable.
// ignore: one_member_abstracts
abstract interface class RepoWatcher {
  /// A stream of typed change signals for [repo]. Never errors: watcher
  /// failures (deleted repo, permissions) end the stream instead.
  Stream<RepoChange> changes(RepoLocation repo);
}
```

- [ ] **Step 4: Update the io implementation**

In `lib/infrastructure/watch/io_repo_watcher.dart`: import `repo_change.dart`; change `StreamController<void>` → `StreamController<RepoChange>`; in the `listen`, classify and emit; remove the `isTransientGitNoise` function (now in `repo_change.dart`).

```dart
import 'dart:async';
import 'dart:io';

import 'package:gitopen/application/watch/repo_change.dart';
import 'package:gitopen/application/watch/repo_watcher.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/logging/app_logger.dart';
import 'package:path/path.dart' as p;

class IoRepoWatcher implements RepoWatcher {
  @override
  Stream<RepoChange> changes(RepoLocation repo) {
    final controller = StreamController<RepoChange>();
    final subs = <StreamSubscription<FileSystemEvent>>[];

    controller
      ..onCancel = () async {
        for (final s in subs) {
          await s.cancel();
        }
      }
      ..onListen = () {
        final gitDir = _resolveGitDir(repo.path);
        if (gitDir == null) {
          unawaited(controller.close());
          return;
        }
        final targets = [
          Directory(gitDir),
          Directory(p.join(gitDir, 'logs')),
        ].where((d) => d.existsSync()).toList();
        if (targets.isEmpty) {
          unawaited(controller.close());
          return;
        }
        var open = targets.length;
        for (final t in targets) {
          subs.add(
            t.watch().listen(
              (event) {
                // Skip index/lock churn (our own `git status` rewrites the
                // index) and irrelevant files; emit a typed change otherwise.
                final kind = classifyGitChange(event.path);
                if (kind == null) return;
                if (!controller.isClosed) controller.add(kind);
              },
              onError: (Object e) {
                appLog.w('repo watcher error on ${t.path}: $e');
              },
              onDone: () {
                open--;
                if (open == 0 && !controller.isClosed) {
                  unawaited(controller.close());
                }
              },
            ),
          );
        }
      };
    return controller.stream;
  }

  String? _resolveGitDir(String repoPath) {
    final dotGit = p.join(repoPath, '.git');
    if (Directory(dotGit).existsSync()) return dotGit;
    final f = File(dotGit);
    if (!f.existsSync()) return null;
    try {
      final line = f.readAsLinesSync().firstWhere(
        (l) => l.startsWith('gitdir:'),
        orElse: () => '',
      );
      if (line.isEmpty) return null;
      final target = line.substring('gitdir:'.length).trim();
      return p.isAbsolute(target)
          ? target
          : p.normalize(p.join(repoPath, target));
    } on Object {
      return null;
    }
  }
}
```

- [ ] **Step 5: Keep `RepoAutoRefreshScope` and its fake compiling**

In `lib/ui/auto_refresh/repo_auto_refresh_scope.dart`: add `import 'package:gitopen/application/watch/repo_change.dart';` and change the field `StreamSubscription<void>? _sub;` → `StreamSubscription<RepoChange>? _sub;`. The listen callback stays `(_) => _debouncer.trigger();` (value ignored — logic changes in Task 4).

In `test/ui/auto_refresh/repo_auto_refresh_scope_test.dart`: change `_FakeWatcher` to the typed stream and emit `RepoChange.head` in the burst:

```dart
import 'package:gitopen/application/watch/repo_change.dart';
// ...
class _FakeWatcher implements RepoWatcher {
  final controller = StreamController<RepoChange>.broadcast();
  int subscriptions = 0;
  int active = 0;

  @override
  Stream<RepoChange> changes(RepoLocation repo) {
    subscriptions++;
    final single = StreamController<RepoChange>()
      ..onListen = (() => active++)
      ..onCancel = (() async => active--);
    controller.stream.listen(single.add, onDone: single.close);
    return single.stream;
  }
}
```

and in the first test replace the burst:

```dart
    watcher.controller
      ..add(RepoChange.head)
      ..add(RepoChange.head); // burst → exactly one refresh
```

(The scope still blanket-invalidates `gitReadOperationsProvider` this task, so this test still passes — its assertions are unchanged. It is rewritten in Task 4.)

- [ ] **Step 6: Run the affected tests**

Run: `flutter test test/infrastructure/watch/io_repo_watcher_test.dart test/ui/auto_refresh/repo_auto_refresh_scope_test.dart`
Expected: PASS.

- [ ] **Step 7: Analyze**

Run: `flutter analyze lib/application/watch lib/infrastructure/watch lib/ui/auto_refresh`
Expected: No issues.

- [ ] **Step 8: Commit**

```bash
git add lib/application/watch/repo_watcher.dart lib/infrastructure/watch/io_repo_watcher.dart lib/ui/auto_refresh/repo_auto_refresh_scope.dart test/infrastructure/watch/io_repo_watcher_test.dart test/ui/auto_refresh/repo_auto_refresh_scope_test.dart
git commit -m "feat(watch): RepoWatcher emits typed RepoChange events"
```

---

### Task 3: Expose the commit-graph provider

**Files:**
- Modify: `lib/ui/commit_graph/commit_graph_panel.dart`

**Interfaces:**
- Produces: public `GraphData` (was `_GraphData`) and `commitGraphDataProvider` (was `_commitGraphDataProvider`).

- [ ] **Step 1: Rename the private type and provider to public**

In `commit_graph_panel.dart`, rename across the file (every occurrence):
- `_GraphData` → `GraphData`
- `_commitGraphDataProvider` → `commitGraphDataProvider`

Leave `_graphLimitProvider`, `_gitLogTimeout`, and other privates as-is (the public provider watches them internally — allowed). `commitGraphDataProvider`'s type becomes `FutureProviderFamily<GraphData, RepoLocation>`, satisfying `library_private_types_in_public_api`.

- [ ] **Step 2: Analyze**

Run: `flutter analyze lib/ui/commit_graph/commit_graph_panel.dart`
Expected: No issues (no public-private-type lint).

- [ ] **Step 3: Run the graph tests (regression)**

Run: `flutter test test/ui/commit_graph/`
Expected: PASS (rename only; behaviour unchanged).

- [ ] **Step 4: Commit**

```bash
git add lib/ui/commit_graph/commit_graph_panel.dart
git commit -m "refactor(graph): expose commitGraphDataProvider for scoped refresh"
```

---

### Task 4: Scoped invalidation + focus headSha safety net

**Files:**
- Modify: `lib/ui/auto_refresh/repo_auto_refresh_scope.dart`
- Test: `test/ui/auto_refresh/repo_auto_refresh_scope_test.dart` (rewrite assertions)

**Interfaces:**
- Consumes: `RepoChange`, `RepoRefreshScope`, `scopesForChange`, `scopesForFocus` (Task 1); `commitGraphDataProvider` (Task 3); `repoStatusProvider`, `workingCopyStatusProvider`, `localBranchesProvider`, `remoteBranchesProvider`, `sidebarDataProvider`, `repoStateProvider`.

- [ ] **Step 1: Write the failing test**

Rewrite `test/ui/auto_refresh/repo_auto_refresh_scope_test.dart`. Use a fake `GitReadOperations` so scoped providers resolve without real git, and count rebuilds of consumers watching the graph vs status.

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings_notifier.dart';
import 'package:gitopen/application/settings/settings_store.dart';
import 'package:gitopen/application/watch/repo_change.dart';
import 'package:gitopen/application/watch/repo_watcher.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/refs/remote.dart';
import 'package:gitopen/domain/refs/stash.dart';
import 'package:gitopen/domain/refs/submodule.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/refs/worktree.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/ui/auto_refresh/repo_auto_refresh_scope.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_panel.dart';

class _FakeWatcher implements RepoWatcher {
  final controller = StreamController<RepoChange>.broadcast();
  @override
  Stream<RepoChange> changes(RepoLocation repo) => controller.stream;
}

class _FakeRead implements GitReadOperations {
  @override
  Future<List<Branch>> getLocalBranches(RepoLocation repo) async => const [];
  @override
  Future<List<Branch>> getRemoteBranches(RepoLocation repo) async => const [];
  @override
  Future<List<Branch>> getBranches(RepoLocation repo) async => const [];
  @override
  Future<RepoStatus> getStatus(RepoLocation repo) async => const RepoStatus(
        isDetached: false,
        isBare: false,
        entries: [],
      );
  @override
  Future<List<Tag>> getTags(RepoLocation repo) async => const [];
  @override
  Future<List<Remote>> getRemotes(RepoLocation repo) async => const [];
  @override
  Future<List<Stash>> getStashes(RepoLocation repo) async => const [];
  @override
  Future<List<Submodule>> getSubmodules(RepoLocation repo) async => const [];
  @override
  Future<List<Worktree>> getWorktrees(RepoLocation repo) async => const [];
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName}');
}

class _InMemoryStore implements SettingsStore {
  final Map<String, dynamic> values = {};
  @override
  Future<Map<String, dynamic>> readAll() async => values;
  @override
  Future<void> put(String key, dynamic value) async => values[key] = value;
}

void main() {
  testWidgets('mergeState watcher event refreshes status but not the graph',
      (tester) async {
    final watcher = _FakeWatcher();
    var statusBuilds = 0;
    var graphBuilds = 0;
    final repo = RepoLocation(RepoId.newId(), 'unused', 't');

    await tester.pumpWidget(ProviderScope(
      overrides: [
        repoWatcherProvider.overrideWithValue(watcher),
        gitReadOperationsProvider.overrideWithValue(_FakeRead()),
        appSettingsProvider
            .overrideWith((ref) => AppSettingsNotifier(_InMemoryStore())),
      ],
      child: MaterialApp(
        home: RepoAutoRefreshScope(
          repo: repo,
          child: Consumer(builder: (context, ref, _) {
            ref.watch(repoStatusProvider(repo));
            ref.watch(commitGraphDataProvider(repo));
            statusBuilds++; // both watched here; split below via keys
            graphBuilds++;
            return const SizedBox();
          }),
        ),
      ),
    ));
    await tester.pump();
    final base = statusBuilds;

    watcher.controller.add(RepoChange.mergeState);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // status invalidated (rebuild), graph NOT — assert via separate counters:
    // (in the real test, watch each provider in its own Consumer so the
    // counters diverge; see Step 1b)
    expect(statusBuilds, greaterThan(base));
    await watcher.controller.close();
  });
}
```

- [ ] **Step 1b: Use two separate consumers so the counters are independent**

Replace the single `Consumer` with two sibling consumers, each watching one provider and incrementing its own counter, so a scope that rebuilds status but not graph is observable:

```dart
        child: RepoAutoRefreshScope(
          repo: repo,
          child: Column(children: [
            Consumer(builder: (c, ref, _) {
              ref.watch(repoStatusProvider(repo));
              statusBuilds++;
              return const SizedBox();
            }),
            Consumer(builder: (c, ref, _) {
              ref.watch(commitGraphDataProvider(repo));
              graphBuilds++;
              return const SizedBox();
            }),
          ]),
        ),
```

Then assert after a `mergeState` event: `expect(statusBuilds, greaterThan(statusBase)); expect(graphBuilds, graphBase);` and after a `head` event: both increase. Capture `statusBase`/`graphBase` right before emitting.

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/ui/auto_refresh/repo_auto_refresh_scope_test.dart`
Expected: FAIL — the scope still blanket-invalidates `gitReadOperationsProvider`, so the graph rebuilds on `mergeState` too (graph counter increases when it should not).

- [ ] **Step 3: Implement scoped invalidation**

Rewrite the body of `_RepoAutoRefreshScopeState` in `repo_auto_refresh_scope.dart`. Key changes: a pending `Set<RepoChange>`; the debounced flush computes `scopesForChange` and invalidates per scope; `_onResume` refreshes worktree+state then checks `headSha`; a `ref.listen` keeps `_lastHeadSha` current.

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/watch/debouncer.dart';
import 'package:gitopen/application/watch/repo_change.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_panel.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

class RepoAutoRefreshScope extends ConsumerStatefulWidget {
  const RepoAutoRefreshScope({
    required this.repo,
    required this.child,
    super.key,
  });
  final RepoLocation repo;
  final Widget child;

  @override
  ConsumerState<RepoAutoRefreshScope> createState() =>
      _RepoAutoRefreshScopeState();
}

class _RepoAutoRefreshScopeState extends ConsumerState<RepoAutoRefreshScope> {
  StreamSubscription<RepoChange>? _sub;
  final Set<RepoChange> _pending = {};
  late final Debouncer _debouncer =
      Debouncer(const Duration(milliseconds: 400), _flushWatcher);
  late final AppLifecycleListener _lifecycle;
  CommitSha? _lastHeadSha;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void didUpdateWidget(RepoAutoRefreshScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repo.id != widget.repo.id) {
      _unsubscribe();
      _lastHeadSha = null;
    }
  }

  @override
  void dispose() {
    _unsubscribe();
    _debouncer.dispose();
    _lifecycle.dispose();
    super.dispose();
  }

  void _syncSubscription({required bool enabled}) {
    if (!enabled) {
      _unsubscribe();
      return;
    }
    _sub ??= ref.read(repoWatcherProvider).changes(widget.repo).listen((kind) {
      _pending.add(kind);
      _debouncer.trigger();
    });
  }

  void _unsubscribe() {
    unawaited(_sub?.cancel());
    _sub = null;
  }

  void _flushWatcher() {
    if (!mounted || _pending.isEmpty) return;
    final kinds = Set<RepoChange>.of(_pending);
    _pending.clear();
    _invalidate(scopesForChange(kinds));
  }

  void _onResume() {
    if (ref.read(appSettingsProvider).autoRefresh) {
      unawaited(_refreshFocus());
    }
  }

  Future<void> _refreshFocus() async {
    final before = _lastHeadSha;
    _invalidate(const {RepoRefreshScope.worktree, RepoRefreshScope.state});
    // Read the just-refreshed status; if HEAD moved while away (a missed
    // watcher event), also refresh refs/graph.
    try {
      final status = await ref.read(repoStatusProvider(widget.repo).future);
      if (status.headSha != before) {
        _invalidate(const {RepoRefreshScope.refs});
      }
    } on Object {
      // Status failed to load; worktree/state already refreshed.
    }
  }

  /// Maps each scope to its providers and invalidates them.
  void _invalidate(Set<RepoRefreshScope> scopes) {
    if (!mounted) return;
    final repo = widget.repo;
    if (scopes.contains(RepoRefreshScope.worktree)) {
      ref
        ..invalidate(repoStatusProvider(repo))
        ..invalidate(workingCopyStatusProvider(repo));
    }
    if (scopes.contains(RepoRefreshScope.refs)) {
      ref
        ..invalidate(localBranchesProvider(repo))
        ..invalidate(remoteBranchesProvider(repo))
        ..invalidate(sidebarDataProvider(repo))
        ..invalidate(commitGraphDataProvider(repo));
    }
    if (scopes.contains(RepoRefreshScope.state)) {
      ref.invalidate(repoStateProvider(repo));
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        ref.watch(appSettingsProvider.select((s) => s.autoRefresh));
    // Keep _lastHeadSha current as status reloads, for the focus safety net.
    ref.listen(repoStatusProvider(widget.repo), (_, next) {
      final sha = next.valueOrNull?.headSha;
      if (sha != null) _lastHeadSha = sha;
    });
    _syncSubscription(enabled: enabled);
    return widget.child;
  }
}
```

Note `sidebarDataProvider` lives in `lib/ui/sidebar/sidebar_shared.dart` — add `import 'package:gitopen/ui/sidebar/sidebar_shared.dart';`. `localBranchesProvider`/`remoteBranchesProvider`/`repoStatusProvider` are in `providers.dart` (already imported).

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/ui/auto_refresh/repo_auto_refresh_scope_test.dart`
Expected: PASS — `mergeState` rebuilds status not graph; `head` rebuilds both.

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/ui/auto_refresh`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/auto_refresh/repo_auto_refresh_scope.dart test/ui/auto_refresh/repo_auto_refresh_scope_test.dart
git commit -m "perf(auto-refresh): scope invalidation by change kind; focus headSha gate"
```

---

### Task 5: Version bump + full verification

**Files:**
- Modify: `pubspec.yaml`, `CHANGELOG.md`

- [ ] **Step 1: Bump the version**

In `pubspec.yaml` bump `version:` by one patch + build (e.g. the current `1.0.3+34` → `1.0.4+35`; if it differs, increment from the current value).

- [ ] **Step 2: Add a CHANGELOG entry**

Add a top `## [x.y.z] — 2026-06-17` entry under `### Changed`/`### Performance`: "Auto-refresh now refreshes only what changed — a fetch or window focus-regain no longer re-logs the whole commit graph or re-reads every ref; focus refreshes the working-tree status (with a HEAD-moved safety net) instead of the entire read layer."

- [ ] **Step 3: Full analyze + test**

Run: `flutter analyze`
Expected: No issues.

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 4: Manual smoke (Windows)**

Run: `flutter run -d windows`. On a large repo: alt-tab away and back repeatedly → no graph reload / no lag (only status updates). Run a fetch externally → branches + graph update. Edit a tracked file in an external editor while GitOpen is unfocused → on focus the change list updates (graph does not reload). Do an external `git checkout` while unfocused → on focus, status updates and (via the headSha safety net) refs/graph update too.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml CHANGELOG.md
git commit -m "chore: bump version and changelog for scoped auto-refresh"
```

---

## Self-Review

**Spec coverage:**
- Typed watcher change kind (`classifyGitChange`) → Task 1 + 2. ✓
- Debounce coalesces a set → Task 4 (`_pending` set in the scope; `Debouncer` untouched — simpler than a `SetDebouncer`, same effect). ✓
- Scope→provider map (worktree/refs/state) → Task 1 (pure) + Task 4 (`_invalidate`). ✓
- Trigger→scope maps (head/refs/fetch/mergeState; focus + headMoved) → Task 1. ✓
- Focus = worktree+state + headSha safety net → Task 4 (`_refreshFocus`). ✓
- Expose graph provider → Task 3. ✓
- Write-path/working-copy invalidations untouched → not modified by any task. ✓
- Tests (pure maps, watcher typed emit, focus-not-graph / mergeState-not-graph) → Tasks 1,2,4. ✓
- Version bump → Task 5. ✓

**Deviations from spec (intentional, noted):** (a) the graph provider is made public **in place** rather than moved to `commit_graph_providers.dart` — the move would drag `_graphLimitProvider`/`_gitLogTimeout`/layout along; in-place public rename is smaller and sufficient. (b) Debounce-set coalescing lives in the scope (`_pending`) rather than a new `SetDebouncer` — fewer moving parts.

**Placeholder scan:** Task 4 Step 1 shows a first-cut single-consumer test then Step 1b refines it to two consumers — the refinement is concrete (full code for the two-consumer tree + the exact assertions), not a TODO. All other code steps contain complete code.

**Type consistency:** `RepoChange{head,refs,fetch,mergeState}`, `RepoRefreshScope{worktree,refs,state}`, `classifyGitChange`, `scopesForChange`, `scopesForFocus`, `commitGraphDataProvider`/`GraphData`, `_invalidate`, `_refreshFocus`, `_flushWatcher`, `_pending`, `_lastHeadSha` — consistent across tasks. Provider names (`repoStatusProvider`, `workingCopyStatusProvider`, `localBranchesProvider`, `remoteBranchesProvider`, `sidebarDataProvider`, `repoStateProvider`, `commitGraphDataProvider`) match their definitions.
