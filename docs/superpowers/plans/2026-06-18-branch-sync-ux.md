# Branch Sync UX — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ahead/behind badges on sidebar branches and the repo name, `git fetch --prune`, and a modal overlay that blocks interaction while any git operation runs (Cancel for network ops).

**Architecture:** A pure `parseAheadBehind` shared by the remote reader and a new perf-bounded `localBranchDivergence` reader exposed via an async provider (so the fast branch load is unaffected). A `BusyNotifier` counter, incremented around every controller action, drives a `BlockingOverlay`; network-op cancel reuses the existing operations `onCancel`/`cancel` (process killed on stream-subscription cancel).

**Tech Stack:** Dart/Flutter, Riverpod, flutter_test, git CLI.

## Global Constraints

- `flutter test <path>`; `flutter analyze` (CI runs analyze with infos fatal; keep lines ≤ 80, no `<...>` in doc comments unless backticked).
- The badge reads `↑ahead ↓behind`; omit a zero side; nothing when 0/0.
- Per-branch ahead/behind must NOT be added to `_forEachRef` (it's deliberately omitted for perf) — use the separate divergence reader.
- `fetch` always prunes.
- Overlay blocks ALL controller actions; Cancel only for network ops.
- Commit messages end with the `Co-Authored-By` trailer shown in the steps.

---

### Task 1: Fetch prunes (Part C)

**Files:**
- Modify: `lib/infrastructure/git/git_cli_sync_writer.dart` (`fetch`)
- Test: `test/infrastructure/git/git_cli_write_operations_fetch_test.dart`

**Interfaces:** Consumes nothing new. Produces no API change (behavioural).

- [ ] **Step 1: Add a failing test**

Append to `test/infrastructure/git/git_cli_write_operations_fetch_test.dart` (reuse its fixture/bare-remote setup pattern; if the file lacks a prune case, model it on the pull/push test's bare-remote setup):

```dart
  test('fetch prunes a remote branch deleted on the remote', () async {
    final seed = await RepoFixture.withLinearHistory(1);
    final bareDir = Directory.systemTemp.createTempSync('gitopen-test-bare-');
    await Process.run(
        'git', ['clone', '--bare', '--local', seed.path, bareDir.path]);
    try {
      await Process.run('git', ['remote', 'add', 'origin', bareDir.path],
          workingDirectory: seed.path);
      await Process.run('git', ['branch', 'feature'], workingDirectory: seed.path);
      await Process.run('git', ['push', 'origin', 'feature'],
          workingDirectory: seed.path);
      await Process.run('git', ['fetch', 'origin'], workingDirectory: seed.path);
      // Delete it on the remote, then fetch (with prune) from the work repo.
      await Process.run(
          'git', ['-C', bareDir.path, 'branch', '-D', 'feature']);

      final ops = GitCliWriteOperations();
      await ops
          .fetch(RepoLocation(const RepoId('r'), seed.path, 'w'), remote: 'origin')
          .drain<void>();

      final refs = await Process.run('git',
          ['for-each-ref', '--format=%(refname)', 'refs/remotes/origin/feature'],
          workingDirectory: seed.path);
      expect((refs.stdout as String).trim(), isEmpty); // pruned
    } finally {
      await seed.dispose();
      bareDir.deleteSync(recursive: true);
    }
  });
```

Ensure the file imports `dart:io`, `RepoId`, `RepoLocation`, `GitCliWriteOperations`, `RepoFixture` (the pull/push test shows them).

- [ ] **Step 2: Run — expect FAIL** (the stale ref is still present)

Run: `flutter test test/infrastructure/git/git_cli_write_operations_fetch_test.dart`
Expected: the new test FAILS (ref not pruned).

- [ ] **Step 3: Implement**

In `git_cli_sync_writer.dart`, change `fetch`'s arg list:

```dart
  Stream<GitProgress> fetch(
    RepoLocation r, {
    String? remote,
    bool all = false,
    AuthSpec? auth,
  }) async* {
    final args = <String>['fetch', '--prune', '--progress'];
    if (all) {
      args.add('--all');
    } else if (remote != null) {
      args.add(remote);
    }
    await for (final p in _runProgressStream(r.path, args, auth: auth)) {
      yield p;
    }
  }
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/infrastructure/git/git_cli_sync_writer.dart test/infrastructure/git/git_cli_write_operations_fetch_test.dart
git commit -m "feat(git): prune deleted remote branches on fetch

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Pure `parseAheadBehind` (Part A1)

**Files:**
- Create: `lib/infrastructure/git/ahead_behind.dart`
- Modify: `lib/infrastructure/git/git_cli_ref_reader.dart` (reuse it in the remote reader)
- Test: `test/infrastructure/git/ahead_behind_test.dart` (create)

**Interfaces:** Produces `({int ahead, int behind}) parseAheadBehind(String track)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/git/ahead_behind.dart';

void main() {
  test('parses ahead+behind, single sides, gone, empty', () {
    expect(parseAheadBehind('[ahead 2, behind 3]'), (ahead: 2, behind: 3));
    expect(parseAheadBehind('[ahead 2]'), (ahead: 2, behind: 0));
    expect(parseAheadBehind('[behind 1]'), (ahead: 0, behind: 1));
    expect(parseAheadBehind('[gone]'), (ahead: 0, behind: 0));
    expect(parseAheadBehind(''), (ahead: 0, behind: 0));
  });
}
```

- [ ] **Step 2: Run — expect FAIL** (`ahead_behind.dart` missing)

- [ ] **Step 3: Implement**

Create `lib/infrastructure/git/ahead_behind.dart`:

```dart
/// Parses git's `%(upstream:track)` value, e.g. `[ahead 2, behind 3]`,
/// `[ahead 2]`, `[behind 1]`, `[gone]`, or `''`, into an (ahead, behind) pair.
({int ahead, int behind}) parseAheadBehind(String track) {
  if (track.isEmpty) return (ahead: 0, behind: 0);
  final m =
      RegExp(r'(?:ahead (\d+))?(?:.*?behind (\d+))?').firstMatch(track);
  if (m == null) return (ahead: 0, behind: 0);
  return (
    ahead: int.tryParse(m.group(1) ?? '') ?? 0,
    behind: int.tryParse(m.group(2) ?? '') ?? 0,
  );
}
```

- [ ] **Step 4: Reuse it in the remote reader**

In `git_cli_ref_reader.dart`, add `import 'package:gitopen/infrastructure/git/ahead_behind.dart';` and replace the inline `aheadBehindRe` block (around lines 274, 302-310) with:

```dart
        final ab = parseAheadBehind(track);
        final ahead = ab.ahead;
        final behind = ab.behind;
```

(delete the `final aheadBehindRe = …` line and the `if (track.isNotEmpty){…}` block that set ahead/behind).

- [ ] **Step 5: Run both — expect PASS**

Run: `flutter test test/infrastructure/git/ahead_behind_test.dart test/infrastructure/git/git_remotes_parse_test.dart`
Expected: PASS (remote parsing still green).

- [ ] **Step 6: Commit**

```bash
git add lib/infrastructure/git/ahead_behind.dart lib/infrastructure/git/git_cli_ref_reader.dart test/infrastructure/git/ahead_behind_test.dart
git commit -m "refactor(git): extract pure parseAheadBehind

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `localBranchDivergence` reader + provider (Part A2)

**Files:**
- Modify: `lib/infrastructure/git/git_cli_ref_reader.dart` (new method)
- Modify: `lib/application/git/git_read_operations.dart` (interface)
- Modify: `lib/infrastructure/git/git_cli_read_operations.dart` (delegation)
- Modify: `lib/application/providers.dart` (`branchDivergenceProvider`)
- Test: `test/infrastructure/git/git_cli_read_operations_divergence_test.dart` (create)

**Interfaces:** Produces `Future<Map<String, ({int ahead, int behind})>> GitReadOperations.localBranchDivergence(RepoLocation)`; `branchDivergenceProvider(RepoLocation)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import '../../_helpers/repo_fixture.dart';

void main() {
  test('reports ahead/behind per local branch vs its upstream', () async {
    final seed = await RepoFixture.withLinearHistory(2);
    final bareDir = Directory.systemTemp.createTempSync('gitopen-test-bare-');
    await Process.run('git', ['clone', '--bare', '--local', seed.path, bareDir.path]);
    try {
      await Process.run('git', ['remote', 'add', 'origin', bareDir.path],
          workingDirectory: seed.path);
      await Process.run('git', ['push', '-u', 'origin', 'master'],
          workingDirectory: seed.path);
      // master ahead by 1
      await Process.run('git', ['commit', '--allow-empty', '-m', 'ahead'],
          workingDirectory: seed.path);

      final ops = GitCliReadOperations();
      final div = await ops.localBranchDivergence(
          RepoLocation(const RepoId('r'), seed.path, 'w'));

      expect(div['master'], (ahead: 1, behind: 0));
    } finally {
      await seed.dispose();
      bareDir.deleteSync(recursive: true);
    }
  });
}
```

(`GitCliReadOperations()` default-constructs like the other read-op tests — confirm against `git_cli_read_operations_refs_test.dart`.)

- [ ] **Step 2: Run — expect FAIL** (`localBranchDivergence` missing)

- [ ] **Step 3: Implement the reader**

In `git_cli_ref_reader.dart`, add (uses the shared parser; bounded with a timeout like remote refs):

```dart
  /// Ahead/behind of each LOCAL branch vs its upstream, keyed by short name.
  /// Uses `%(upstream:track)` (kept OUT of the fast _forEachRef for perf) and
  /// a hard timeout — on a huge repo it returns whatever parsed in time.
  Future<Map<String, ({int ahead, int behind})>> localBranchDivergence(
    RepoLocation repo,
  ) async {
    const fmt = '%(refname:short)%00%(upstream:track)';
    try {
      final out = await _runner
          .run(repo.path, ['for-each-ref', '--format=$fmt', 'refs/heads'])
          .timeout(const Duration(seconds: 3));
      final map = <String, ({int ahead, int behind})>{};
      for (final line in const LineSplitter().convert(out)) {
        if (line.isEmpty) continue;
        final parts = line.split('\x00');
        if (parts.isEmpty) continue;
        final name = parts[0];
        final track = parts.length > 1 ? parts[1] : '';
        final ab = parseAheadBehind(track);
        if (ab.ahead != 0 || ab.behind != 0) map[name] = ab;
      }
      return map;
    } on Object {
      return const {};
    }
  }
```

(Ensure `import 'dart:convert';` is present — it is, for `LineSplitter`/`utf8`.)

- [ ] **Step 4: Expose on the read facade**

In `lib/application/git/git_read_operations.dart` add to the interface:

```dart
  /// Ahead/behind per local branch (short name -> pair). Empty for branches
  /// in sync or without an upstream.
  Future<Map<String, ({int ahead, int behind})>> localBranchDivergence(
    RepoLocation repo,
  );
```

In `lib/infrastructure/git/git_cli_read_operations.dart` add the delegation next to `getLocalBranches` (mirror that one-line delegation to the ref-reader field):

```dart
  @override
  Future<Map<String, ({int ahead, int behind})>> localBranchDivergence(
    RepoLocation repo,
  ) =>
      _refs.localBranchDivergence(repo);
```

(Use the actual ref-reader field name from this file — same field `getLocalBranches` delegates to.)

- [ ] **Step 5: Add the provider**

In `lib/application/providers.dart`, next to `localBranchesProvider`:

```dart
/// Ahead/behind per local branch — loaded in parallel so it never blocks the
/// initial branch render; the sidebar badges fill in when it resolves.
final FutureProviderFamily<Map<String, ({int ahead, int behind})>, RepoLocation>
    branchDivergenceProvider =
    FutureProvider.family<Map<String, ({int ahead, int behind})>, RepoLocation>(
        (ref, repo) {
  return ref.watch(gitReadOperationsProvider).localBranchDivergence(repo);
});
```

- [ ] **Step 6: Run — expect PASS**

Run: `flutter test test/infrastructure/git/git_cli_read_operations_divergence_test.dart`

- [ ] **Step 7: Commit**

```bash
git add lib/infrastructure/git/git_cli_ref_reader.dart lib/application/git/git_read_operations.dart lib/infrastructure/git/git_cli_read_operations.dart lib/application/providers.dart test/infrastructure/git/git_cli_read_operations_divergence_test.dart
git commit -m "feat(git): per-local-branch ahead/behind provider

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `DivergenceBadge` widget + sidebar badge (Part A3)

**Files:**
- Create: `lib/ui/common/divergence_badge.dart`
- Modify: `lib/ui/sidebar/branch_tree_view.dart`
- Test: `test/ui/common/divergence_badge_test.dart` (create)

**Interfaces:** Produces `DivergenceBadge(ahead:, behind:)` — renders nothing when both 0.

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/common/divergence_badge.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

Future<void> _pump(WidgetTester t, int ahead, int behind) => t.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Scaffold(body: DivergenceBadge(ahead: ahead, behind: behind)),
      ),
    );

void main() {
  testWidgets('shows both arrows', (t) async {
    await _pump(t, 2, 3);
    expect(find.text('↑2'), findsOneWidget);
    expect(find.text('↓3'), findsOneWidget);
  });
  testWidgets('omits the zero side', (t) async {
    await _pump(t, 2, 0);
    expect(find.text('↑2'), findsOneWidget);
    expect(find.textContaining('↓'), findsNothing);
  });
  testWidgets('renders nothing when in sync', (t) async {
    await _pump(t, 0, 0);
    expect(find.textContaining('↑'), findsNothing);
    expect(find.textContaining('↓'), findsNothing);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement the widget**

Create `lib/ui/common/divergence_badge.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Small `↑ahead ↓behind` badge for a branch's divergence from its upstream.
/// Renders an empty box when both are zero.
class DivergenceBadge extends StatelessWidget {
  const DivergenceBadge({required this.ahead, required this.behind, super.key});
  final int ahead;
  final int behind;

  @override
  Widget build(BuildContext context) {
    if (ahead == 0 && behind == 0) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final parts = <String>[
      if (ahead > 0) '↑$ahead',
      if (behind > 0) '↓$behind',
    ];
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        parts.join(' '),
        style: TextStyle(
          color: palette.fg2,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Wire into the sidebar branch row**

In `branch_tree_view.dart`: add imports for `branchDivergenceProvider` (from providers) and `DivergenceBadge`. In `_renderNode`, for a leaf branch that is local (`branch != null && !branch.isRemote`), read the divergence map and insert the badge after the branch name `Expanded` (before the visibility eye):

```dart
                  if (branch != null && !branch.isRemote)
                    Consumer(
                      builder: (context, ref, _) {
                        final div = ref
                            .watch(branchDivergenceProvider(widget.repo))
                            .valueOrNull?[branch.name];
                        return DivergenceBadge(
                          ahead: div?.ahead ?? 0,
                          behind: div?.behind ?? 0,
                        );
                      },
                    ),
```

(Place it inside the `Row(children: [...])` of the leaf row, right after the name `Expanded(...)`.)

- [ ] **Step 6: Run the sidebar widget tests + analyze the file**

Run: `flutter test test/ui/sidebar/`
Run: `flutter analyze lib/ui/sidebar/branch_tree_view.dart lib/ui/common/divergence_badge.dart`
Expected: PASS / no issues.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/common/divergence_badge.dart lib/ui/sidebar/branch_tree_view.dart test/ui/common/divergence_badge_test.dart
git commit -m "feat(ui): ahead/behind badge on sidebar branches

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Repo-name badge (Part A4)

**Files:**
- Modify: `lib/ui/shell/repo_selector.dart`

**Interfaces:** Consumes `repoStatusProvider` (existing FutureProvider.family) + `DivergenceBadge` (Task 4).

> **No new unit test:** presentational reuse of `DivergenceBadge` (tested) and
> `repoStatusProvider` (existing). Verified by analyze + manual.

- [ ] **Step 1: Add the badge to the selector button**

In `repo_selector.dart`, the `_SelectorButton` shows the label. In `_RepoSelectorState.build`, when `active != null`, compute the current-branch divergence from `repoStatusProvider(active.location)` and show a `DivergenceBadge` after the label. Add imports for `repoStatusProvider`/`DivergenceBadge`, then in the `Row` of `_SelectorButton` (passed in or rendered in the state), insert after the label `Flexible`:

```dart
            if (active != null)
              Consumer(
                builder: (context, ref, _) {
                  final st = ref
                      .watch(repoStatusProvider(active.location))
                      .valueOrNull;
                  return DivergenceBadge(
                    ahead: st?.ahead ?? 0,
                    behind: st?.behind ?? 0,
                  );
                },
              ),
```

If the badge must live inside `_SelectorButton` (which only gets `label`), pass `ahead`/`behind` ints into `_SelectorButton` instead and render `DivergenceBadge` there. Choose whichever keeps `_SelectorButton` cohesive; the data comes from `repoStatusProvider(active.location)` read in `_RepoSelectorState`.

- [ ] **Step 2: Verify analyze + sidebar/shell tests**

Run: `flutter analyze lib/ui/shell/repo_selector.dart`
Run: `flutter test test/ui/shell/`
Expected: no issues / PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/ui/shell/repo_selector.dart
git commit -m "feat(ui): ahead/behind badge on the repo name

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: `BusyNotifier` + controller wrap (Part B1)

**Files:**
- Create: `lib/application/operations/busy_notifier.dart`
- Modify: `lib/application/providers.dart` (`busyProvider`)
- Modify: `lib/ui/git/git_actions_controller.dart` (`_run`, `_runLocal`)
- Test: `test/application/operations/busy_notifier_test.dart` (create)

**Interfaces:** Produces `class BusyState { int depth; String? label; }`; `BusyNotifier` with `begin(String label)` / `end()`; `busyProvider` (StateNotifierProvider<BusyNotifier, BusyState>). `bool get isBusy => depth > 0`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/operations/busy_notifier.dart';

void main() {
  test('nested begin/end tracks depth and clears label at zero', () {
    final n = BusyNotifier();
    expect(n.state.depth, 0);
    n.begin('Fetching');
    expect(n.state.depth, 1);
    expect(n.state.label, 'Fetching');
    n.begin('Checking out x');
    expect(n.state.depth, 2);
    expect(n.state.label, 'Checking out x');
    n.end();
    expect(n.state.depth, 1);
    n.end();
    expect(n.state.depth, 0);
    expect(n.state.label, isNull);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement**

Create `lib/application/operations/busy_notifier.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether a blocking git operation is in flight, and its label.
class BusyState extends Equatable {
  const BusyState({this.depth = 0, this.label});
  final int depth;
  final String? label;

  bool get isBusy => depth > 0;

  @override
  List<Object?> get props => [depth, label];
}

/// Counts in-flight controller actions so the UI can block interaction. A
/// counter (not a bool) so nested operations keep the overlay up until all
/// finish. [label] is the most recently started op (shown in the overlay).
class BusyNotifier extends StateNotifier<BusyState> {
  BusyNotifier() : super(const BusyState());

  void begin(String label) =>
      state = BusyState(depth: state.depth + 1, label: label);

  void end() {
    final depth = state.depth - 1;
    state = depth <= 0 ? const BusyState() : BusyState(depth: depth, label: state.label);
  }
}
```

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Add the provider**

In `providers.dart`:

```dart
final busyProvider = StateNotifierProvider<BusyNotifier, BusyState>(
  (ref) => BusyNotifier(),
);
```

(import `busy_notifier.dart`.)

- [ ] **Step 6: Wrap controller actions**

In `git_actions_controller.dart`, import `busy_notifier.dart`. Wrap `_run` and `_runLocal` bodies so each increments/decrements busy with a label. `_run` already takes `context, repo, op`; add an optional `String label` to both, defaulting from the op. Simplest: derive a label from the op kind is hard here, so pass an explicit label. Update `_run`/`_runLocal` signatures to take `String label` and have every caller pass one (e.g. `'Fetching'`, `'Pulling'`, `'Pushing'`, `'Checking out'`, `'Merging'`, …). Then:

```dart
  Future<ActionResult> _run(
    BuildContext context,
    RepoLocation repo,
    String label,
    Future<ActionResult> Function(AuthPrompt prompt, ProgressSink progress) op,
  ) async {
    final busy = _ref.read(busyProvider.notifier);
    busy.begin(label);
    try {
      final result = await op(
        DialogAuthPrompt(context, _ref),
        OperationsProgressSink(_ref),
      );
      _invalidate(repo, result.invalidate);
      final message = result.message;
      if (message != null && context.mounted) {
        _showSnack(context, message, result.severity);
      }
      return result;
    } finally {
      busy.end();
    }
  }
```

(and the analogous change in `_runLocal`). Add `label` args at every call site (each existing method like `fetch`, `pull`, `push`, `checkout`, `merge`, … passes a short present-progressive label).

NOTE: this touches every method in the controller (mechanical). Keep labels short and human ("Fetching", "Checking out", "Merging", "Deleting branch", etc.).

- [ ] **Step 7: Verify analyze + suite**

Run: `flutter analyze`
Run: `flutter test`
Expected: no issues / PASS (controllers compile; nothing visibly blocks yet — overlay is Task 7).

- [ ] **Step 8: Commit**

```bash
git add lib/application/operations/busy_notifier.dart lib/application/providers.dart lib/ui/git/git_actions_controller.dart test/application/operations/busy_notifier_test.dart
git commit -m "feat(ops): busy counter around every git action

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: `BlockingOverlay` + Shell wiring (Part B2)

**Files:**
- Create: `lib/ui/operations/blocking_overlay.dart`
- Modify: `lib/main.dart` (Shell `Stack`)
- Test: `test/ui/operations/blocking_overlay_test.dart` (create)

**Interfaces:** Consumes `busyProvider` (Task 6) + `operationsProvider` (existing). Produces `BlockingOverlay` widget.

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/operations/busy_notifier.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/operations/blocking_overlay.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  testWidgets('hidden when idle, shown + blocks taps when busy', (t) async {
    var tapped = false;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: Stack(
              children: [
                Center(
                  child: GestureDetector(
                    onTap: () => tapped = true,
                    child: const Text('hit me'),
                  ),
                ),
                const BlockingOverlay(),
              ],
            ),
          ),
        ),
      ),
    );

    // Idle: overlay absent, tap passes through.
    expect(find.byType(ModalBarrier), findsNothing);

    container.read(busyProvider.notifier).begin('Fetching');
    await t.pump();
    expect(find.text('Fetching'), findsOneWidget);
    await t.tap(find.text('hit me'), warnIfMissed: false);
    expect(tapped, isFalse); // blocked by the overlay
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement the overlay**

Create `lib/ui/operations/blocking_overlay.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Full-screen modal shown while a git operation runs. Absorbs all input so
/// the user can't navigate or start another action mid-operation. Shows a
/// Cancel button when a cancelable (network) operation is running.
class BlockingOverlay extends ConsumerWidget {
  const BlockingOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(busyProvider);
    if (!busy.isBusy) return const SizedBox.shrink();
    final palette = AppPalette.of(context);

    // Cancel comes from the running network op (registered onCancel).
    final ops = ref.watch(operationsProvider);
    final cancelable = ops
        .where((o) => o.status == OperationStatus.running && o.onCancel != null)
        .firstOrNull;

    return Positioned.fill(
      child: Stack(
        children: [
          const ModalBarrier(dismissible: false, color: Color(0x66000000)),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: palette.bg2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: palette.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    busy.label ?? 'Working…',
                    style: TextStyle(color: palette.fg0, fontSize: 13),
                  ),
                  if (cancelable != null) ...[
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: () => ref
                          .read(operationsProvider.notifier)
                          .cancel(cancelable.id),
                      child: const Text('Cancel'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

(`firstOrNull` is from `package:collection`; import it, or use `cast/where().toList()` and check `isEmpty`.)

- [ ] **Step 4: Run — expect PASS**

- [ ] **Step 5: Wire into the Shell**

In `lib/main.dart`, in the Shell `Stack`, add `const BlockingOverlay()` AFTER `const ToastOverlay()` (so it sits on top). Add the import.

```dart
                  child: Stack(
                    children: [
                      Column(/* … */),
                      const ToastOverlay(),
                      const BlockingOverlay(),
                    ],
                  ),
```

- [ ] **Step 6: Verify analyze + suite**

Run: `flutter analyze`
Run: `flutter test`
Expected: no issues / PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/operations/blocking_overlay.dart lib/main.dart test/ui/operations/blocking_overlay_test.dart
git commit -m "feat(ui): modal overlay blocks interaction during git operations

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Cancel for network ops (Part B3)

**Files:**
- Modify: `lib/application/git/git_action_ports.dart` (`ProgressSink.start` gains `onCancel`)
- Modify: `lib/ui/git/git_action_bridges.dart` (`OperationsProgressSink.start` forwards `onCancel`)
- Modify: `lib/application/git/git_actions_service.dart` (`_runStream` subscription + cancel)
- Modify: `lib/infrastructure/git/git_cli_sync_writer.dart` (`_runProgressStream` kills the process on cancel)
- Modify: `test/application/git/git_actions_service_test.dart` (`_FakeProgress.start` signature)

**Interfaces:** Produces `ProgressSink.start(OpKind, String, {RepoLocation? repo, void Function()? onCancel})`. Cancelling a running streaming op kills its git process; the op finishes (failed/cancelled) and busy `end()` runs.

- [ ] **Step 1: Extend `ProgressSink.start`**

In `git_action_ports.dart`:

```dart
  String start(OpKind kind, String label, {RepoLocation? repo, void Function()? onCancel});
```

In `git_action_bridges.dart`, forward it (the notifier's `start` already accepts `onCancel`):

```dart
  @override
  String start(OpKind kind, String label,
          {RepoLocation? repo, void Function()? onCancel}) =>
      _ops.start(kind, label, repo: repo, onCancel: onCancel);
```

In `test/application/git/git_actions_service_test.dart`, update `_FakeProgress.start` to the new signature (ignore `onCancel`):

```dart
  @override
  String start(OpKind kind, String label,
      {RepoLocation? repo, void Function()? onCancel}) {
    final id = 'op${_n++}';
    events.add('start:$id');
    return id;
  }
```

- [ ] **Step 2: Make `_runStream` cancelable**

In `git_actions_service.dart`, replace the `await for` consumption in `_runStream` with a subscription whose cancel is registered as the op's `onCancel`:

```dart
    final resolved = profileResolved ? profile : await _resolveProfile(repo);
    StreamSubscription<GitProgress>? sub;
    final done = Completer<void>();
    var cancelled = false;
    final id = progress.start(
      kind,
      label,
      repo: repo,
      onCancel: () {
        cancelled = true;
        unawaited(sub?.cancel());
        if (!done.isCompleted) done.complete();
      },
    );
    sub = streamFactory(resolved?.spec).listen(
      (ev) => progress.progress(id, ev.fraction, ev.phase),
      onError: (Object e, StackTrace s) {
        if (!done.isCompleted) done.completeError(e, s);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    try {
      await done.future;
      if (cancelled) {
        progress.failure(id, 'Cancelled');
        return const ActionResult(ActionOutcome.failed);
      }
      progress.success(id);
      return const ActionResult.reads(ActionOutcome.success);
    } on Object catch (e) {
      // (existing auth-classify + prompt + retry block, unchanged)
      ...
    }
```

Keep the existing `catch` body (auth classification, prompt, recursive retry) exactly as-is. Add `import 'dart:async';` if not present.

- [ ] **Step 3: Kill the process on cancel in the sync writer**

In `git_cli_sync_writer.dart` `_runProgressStream`, hold the process and kill it in `finally` (safe no-op if already exited; only actually kills when the stream was cancelled mid-flight):

```dart
    Process? proc;
    final stderrBuf = StringBuffer();
    try {
      proc = await Process.start(
        _runner.executable,
        effectiveArgs,
        workingDirectory: cwd,
        environment: buildGitEnvironment(helper.env),
      );
      // … existing drain + stderr loop + exitCode/throw …
    } finally {
      helper.dispose();
      proc?.kill(); // no-op if already exited; kills if the consumer cancelled
    }
```

- [ ] **Step 4: Run the targeted suites — expect PASS**

Run: `flutter test test/application/git/ test/infrastructure/git/git_cli_write_operations_pull_push_test.dart test/infrastructure/git/git_cli_write_operations_fetch_test.dart`
Expected: PASS (service auth-retry tests still green with the new subscription path; fetch/push still work).

- [ ] **Step 5: Verify analyze + full suite**

Run: `flutter analyze`
Run: `flutter test`
Expected: no issues / PASS.

- [ ] **Step 6: Manual smoke (cancel)**

1. `flutter run -d windows`; trigger a Fetch on a repo with a slow/large remote → overlay appears with "Fetching" + Cancel; clicking Cancel ends it (process killed), overlay clears.
2. Trigger a checkout → overlay appears (no Cancel), clears when done.

- [ ] **Step 7: Commit**

```bash
git add lib/application/git/git_action_ports.dart lib/ui/git/git_action_bridges.dart lib/application/git/git_actions_service.dart lib/infrastructure/git/git_cli_sync_writer.dart test/application/git/git_actions_service_test.dart
git commit -m "feat(ops): cancel an in-flight network op (kills the git process)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:** Prune → T1. Divergence data → T2 (parser) + T3 (reader/provider). Sidebar badge → T4. Repo-name badge → T5. Busy block → T6 + T7. Cancel network ops → T8. ✓

**Placeholder scan:** The controller wrap (T6 step 6) and a couple of facade delegations say "mirror the existing pattern / pass a label at each call site" — these are mechanical, repeated edits over many call sites, not vague logic; the pattern and the exact wrapper code are given. The T8 `_runStream` catch block is referenced as "unchanged" (it already exists verbatim in the file).

**Type consistency:** `({int ahead, int behind})` record used consistently in `parseAheadBehind`, `localBranchDivergence`, `branchDivergenceProvider`, `DivergenceBadge` inputs. `BusyState{depth,label,isBusy}` / `BusyNotifier.begin/end` consistent T6→T7. `ProgressSink.start(... onCancel)` consistent T8 across port/bridge/service/fake.

**Risk note:** T8 (cancel) is the most involved — it changes the streaming consumption path. The auth-retry behaviour must stay identical; the targeted service tests in T8 step 4 guard it. T1–T7 deliver the full feature even if T8 needs iteration.
