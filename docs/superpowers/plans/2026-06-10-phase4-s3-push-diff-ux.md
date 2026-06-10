# Phase 4 — S3 Advanced Push + Diff UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Push split-button (force-with-lease behind confirm, push tags, push specific branch→remote) and diff view modes (side-by-side toggle + ignore-whitespace).

**Architecture:** `GitActionsService.push`/controller `push` gain the optional knobs the write layer already supports (`remote`, `branch`, `forceWithLease`, `pushTags`). The toolbar Push becomes button + caret opening an `AppContextMenu`. Side-by-side is a pure pairing (`buildSplitRows` over `pairChangedLines`) rendered by `SplitHunkLines`; `HunkLines` switches on a session `diffViewModeProvider`. Ignore-whitespace is a session pref passed to `getDiff` (`-w`), applied ONLY to the commit diff view — never the working-copy preview, whose hunks feed `buildPatchForHunks` and must match the index byte-for-byte.

**Tech Stack:** Flutter/Dart, riverpod; no new deps.

**Branch:** `feat/phase4-s3-push-diff-ux` from main (after S2 merges). Version → `0.1.15+16`.

**Commands** (from `D:\repos\Personal\GitOpen`): test `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test <path>`; analyze `& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze`. No blanket `dart format`.

## File Structure

| File | Change |
|---|---|
| `lib/application/git/git_actions_service.dart:140-153` | push gains optional knobs |
| `lib/ui/git/git_actions_controller.dart:65-73` | same knobs |
| `lib/ui/toolbar/git_toolbar.dart:71-77,94-95` | split-button + menu + dialogs |
| `lib/ui/dialogs/push_branch_dialog.dart` | NEW branch→remote picker |
| `lib/application/diff/split_diff.dart` | NEW pure `buildSplitRows` |
| `lib/ui/common/diff_prefs.dart` | + `diffViewModeProvider`, `ignoreWhitespaceProvider`, toggles |
| `lib/ui/common/diff_line_row.dart` | `HunkLines` switches mode; + `SplitHunkLines` + `_SplitLineRow` |
| `lib/application/git/git_read_operations.dart` | getDiff/getDiffForFile gain `ignoreWhitespace` |
| `lib/infrastructure/git/git_cli_file_reader.dart` | `-w` arg |
| `lib/infrastructure/git/git_cli_read_operations.dart` | pass-through |
| `lib/ui/bottom_panel/diff_view.dart` | pass pref to providers; whitespace toggle in header |
| tests | service push args; split rows unit; `-w` infra; existing suites |

---

### Task 1: Service/controller push knobs (TDD)

**Files:** Modify `lib/application/git/git_actions_service.dart`, `lib/ui/git/git_actions_controller.dart`; Test `test/application/git/git_actions_service_test.dart`

- [ ] **Step 1: Extend `_FakeWrite`** in the service test with `bool? lastPushForce;` recorded in `push` (`lastPushForce = forceWithLease;`). Add tests at the end of `main()`:

```dart
  test('push forwards forceWithLease / branch / remote / tags', () async {
    final write = _FakeWrite([_ok]);
    final prompt = _FakePrompt(null);
    final progress = _FakeProgress();

    final result = await service(write).push(
      repo,
      remote: 'origin',
      branch: 'feature/x',
      forceWithLease: true,
      prompt: prompt,
      progress: progress,
    );

    expect(result.outcome, ActionOutcome.success);
    expect(write.lastPushRemote, 'origin');
    expect(write.lastPushBranch, 'feature/x');
    expect(write.lastPushForce, isTrue);
    expect(write.lastPushTags, isFalse);
  });

  test('push --tags only', () async {
    final write = _FakeWrite([_ok]);
    final prompt = _FakePrompt(null);
    final progress = _FakeProgress();

    await service(write)
        .push(repo, pushTags: true, prompt: prompt, progress: progress);

    expect(write.lastPushTags, isTrue);
    expect(write.lastPushBranch, isNull);
  });
```

- [ ] **Step 2: Run — compile failure** (named params unknown).
- [ ] **Step 3: Implement** — service `push` becomes:

```dart
  /// `git push` with progress + auth-retry. The optional knobs map straight
  /// onto the write op: [remote]+[branch] push one ref, [forceWithLease]
  /// adds --force-with-lease, [pushTags] adds --tags.
  Future<ActionResult> push(
    RepoLocation repo, {
    required AuthPrompt prompt,
    required ProgressSink progress,
    String? remote,
    String? branch,
    bool forceWithLease = false,
    bool pushTags = false,
  }) {
    final label = forceWithLease
        ? 'Force-pushing'
        : pushTags
            ? 'Pushing tags'
            : branch != null
                ? 'Pushing $branch'
                : 'Pushing';
    return _runStream(
      OpKind.push,
      label,
      repo,
      (auth) => _write.push(
        repo,
        remote: remote,
        branch: branch,
        forceWithLease: forceWithLease,
        pushTags: pushTags,
        auth: auth,
      ),
      prompt: prompt,
      progress: progress,
    );
  }
```

Controller `push` mirrors the same optional params and forwards them.

- [ ] **Step 4: Run service tests — PASS. Commit** `feat(phase4): expose push knobs (force-with-lease, branch/remote, tags) through the facade`

---

### Task 2: Toolbar split-button + PushBranchDialog

**Files:** Create `lib/ui/dialogs/push_branch_dialog.dart`; Modify `lib/ui/toolbar/git_toolbar.dart`

- [ ] **Step 1: `PushBranchDialog`** — two dropdowns fed by read ops; returns `({String branch, String remote})?`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Picks a local branch and a remote for an explicit `git push <remote>
/// <branch>`. Returns null when cancelled.
class PushBranchDialog {
  static Future<({String branch, String remote})?> show(
    BuildContext context,
    WidgetRef ref,
    RepoLocation repo,
  ) async {
    final read = ref.read(gitReadOperationsProvider);
    final branches = await read.getLocalBranches(repo);
    final remotes = await read.getRemotes(repo);
    if (!context.mounted || branches.isEmpty || remotes.isEmpty) return null;
    final current = branches
        .where((b) => b.isCurrent)
        .map((b) => b.name)
        .firstOrNull;
    var branch = current ?? branches.first.name;
    var remote = remotes.first.name;
    return showDialog<({String branch, String remote})>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setState) => AppDialog(
            title: 'Push branch',
            width: 420,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: branch,
                  decoration: appInputDecoration(ctx, label: 'Branch'),
                  dropdownColor: palette.bg2,
                  style: TextStyle(color: palette.fg0, fontSize: 13),
                  items: [
                    for (final b in branches)
                      DropdownMenuItem(value: b.name, child: Text(b.name)),
                  ],
                  onChanged: (v) => setState(() => branch = v ?? branch),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: remote,
                  decoration: appInputDecoration(ctx, label: 'Remote'),
                  dropdownColor: palette.bg2,
                  style: TextStyle(color: palette.fg0, fontSize: 13),
                  items: [
                    for (final r in remotes)
                      DropdownMenuItem(value: r.name, child: Text(r.name)),
                  ],
                  onChanged: (v) => setState(() => remote = v ?? remote),
                ),
              ],
            ),
            actions: [
              AppButton.secondary(
                label: 'Cancel',
                onPressed: () => Navigator.pop(ctx),
              ),
              AppButton.primary(
                label: 'Push',
                onPressed: () =>
                    Navigator.pop(ctx, (branch: branch, remote: remote)),
              ),
            ],
          ),
        );
      },
    );
  }
}
```

(`DropdownButtonFormField` parameter name: use `value:` if `initialValue:` doesn't exist in this Flutter version. `firstOrNull` needs `package:collection` — already used by main.dart — or fall back to a loop.)

- [ ] **Step 2: Toolbar** — in `git_toolbar.dart` replace the Push `ToolbarButton` with the button + caret pair:

```dart
        ToolbarButton(
          icon: Icons.north,
          label: 'Push',
          enabled: enabled,
          tooltip: 'Push to origin',
          onTap: () => _push(repo!),
        ),
        _PushMenuCaret(enabled: enabled, onOpen: (pos) => _pushMenu(repo!, pos)),
```

with (in the same file):

```dart
/// Narrow caret that opens the advanced-push menu, visually attached to the
/// Push button.
class _PushMenuCaret extends StatelessWidget {
  const _PushMenuCaret({required this.enabled, required this.onOpen});
  final bool enabled;
  final void Function(Offset globalPosition) onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: InkWell(
        onTapDown: enabled ? (d) => onOpen(d.globalPosition) : null,
        onTap: enabled ? () {} : null,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Icon(Icons.expand_more, size: 12, color: palette.fg2),
        ),
      ),
    );
  }
}
```

and the handler methods on the toolbar state:

```dart
  Future<void> _pushMenu(RepoLocation repo, Offset pos) async {
    final selected = await AppContextMenu.show<String>(
      context,
      globalPosition: pos,
      entries: const [
        AppMenuItem(value: 'push', label: 'Push', icon: Icons.north),
        AppMenuItem(
          value: 'force',
          label: 'Force push (--force-with-lease)',
          icon: Icons.warning_amber_outlined,
          danger: true,
        ),
        AppMenuItem(
          value: 'tags',
          label: 'Push tags',
          icon: Icons.local_offer_outlined,
        ),
        AppMenuItem(
          value: 'branch',
          label: 'Push branch…',
          icon: Icons.alt_route,
        ),
      ],
    );
    if (selected == null || !mounted) return;
    final actions = ref.read(gitActionsControllerProvider);
    switch (selected) {
      case 'push':
        await actions.push(context, repo);
      case 'force':
        final confirmed = await ConfirmDialog.show(
          context,
          title: 'Force push',
          body: 'Force-push with --force-with-lease? This rewrites the '
              'remote branch, but refuses if someone else pushed first.',
          confirmLabel: 'Force push',
          dangerous: true,
        );
        if (!confirmed || !mounted) return;
        await actions.push(context, repo, forceWithLease: true);
      case 'tags':
        await actions.push(context, repo, pushTags: true);
      case 'branch':
        final picked = await PushBranchDialog.show(context, ref, repo);
        if (picked == null || !mounted) return;
        await actions.push(
          context,
          repo,
          remote: picked.remote,
          branch: picked.branch,
        );
    }
  }
```

Add the imports (`app_context_menu.dart`, `confirm_dialog.dart`, `push_branch_dialog.dart`).

- [ ] **Step 3: analyze clean. Commit** `feat(phase4): push split-button — force-with-lease, tags, explicit branch/remote`

---

### Task 3: Side-by-side diff (pure pairing + renderer)

**Files:** Create `lib/application/diff/split_diff.dart`; Modify `lib/ui/common/diff_prefs.dart`, `lib/ui/common/diff_line_row.dart`; Test `test/application/diff/split_diff_test.dart`

- [ ] **Step 1: Failing pure test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/diff/split_diff.dart';
import 'package:gitopen/domain/diff/diff_line.dart';

DiffLine _l(DiffLineKind k, String c) => DiffLine(kind: k, content: c);

void main() {
  test('context lines occupy both sides', () {
    final rows = buildSplitRows([_l(DiffLineKind.context, 'a')]);
    expect(rows.single.left?.content, 'a');
    expect(rows.single.right?.content, 'a');
  });

  test('paired deletion/addition share one row', () {
    final rows = buildSplitRows([
      _l(DiffLineKind.deletion, 'old'),
      _l(DiffLineKind.addition, 'new'),
    ]);
    expect(rows, hasLength(1));
    expect(rows.single.left?.content, 'old');
    expect(rows.single.right?.content, 'new');
  });

  test('unbalanced run pads the short side', () {
    final rows = buildSplitRows([
      _l(DiffLineKind.deletion, 'a'),
      _l(DiffLineKind.deletion, 'b'),
      _l(DiffLineKind.addition, 'x'),
    ]);
    expect(rows, hasLength(2));
    expect(rows[0].left?.content, 'a');
    expect(rows[0].right?.content, 'x');
    expect(rows[1].left?.content, 'b');
    expect(rows[1].right, isNull);
  });
}
```

- [ ] **Step 2: Implement `lib/application/diff/split_diff.dart`**

```dart
import 'package:gitopen/domain/diff/diff_line.dart';

/// One side-by-side row: deletions/context on the [left] (old file),
/// additions/context on the [right] (new file). A null side renders blank.
typedef SplitRow = ({DiffLine? left, DiffLine? right});

/// Folds unified-diff lines into side-by-side rows: context spans both
/// columns; inside each changed run (deletions then additions, unified
/// order) the k-th deletion pairs with the k-th addition, and the longer
/// side trails with blanks.
List<SplitRow> buildSplitRows(List<DiffLine> lines) {
  final rows = <SplitRow>[];
  final deletions = <DiffLine>[];
  final additions = <DiffLine>[];

  void flush() {
    final n = deletions.length > additions.length
        ? deletions.length
        : additions.length;
    for (var k = 0; k < n; k++) {
      rows.add((
        left: k < deletions.length ? deletions[k] : null,
        right: k < additions.length ? additions[k] : null,
      ));
    }
    deletions.clear();
    additions.clear();
  }

  for (final line in lines) {
    switch (line.kind) {
      case DiffLineKind.deletion:
        if (additions.isNotEmpty) flush();
        deletions.add(line);
      case DiffLineKind.addition:
        additions.add(line);
      case DiffLineKind.context:
        flush();
        rows.add((left: line, right: line));
    }
  }
  flush();
  return rows;
}
```

- [ ] **Step 3: Prefs + toggle** — in `diff_prefs.dart`:

```dart
/// How diff hunks are laid out. Session-scoped.
enum DiffViewMode { unified, sideBySide }

final diffViewModeProvider =
    StateProvider<DiffViewMode>((_) => DiffViewMode.unified);

/// Toggle for [diffViewModeProvider], shown next to [WordDiffToggle].
class SplitDiffToggle extends ConsumerWidget {
  const SplitDiffToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final mode = ref.watch(diffViewModeProvider);
    final split = mode == DiffViewMode.sideBySide;
    return Tooltip(
      message: split
          ? 'Side-by-side — click for unified'
          : 'Unified — click for side-by-side',
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        borderRadius: BorderRadius.circular(3),
        onTap: () => ref.read(diffViewModeProvider.notifier).state =
            split ? DiffViewMode.unified : DiffViewMode.sideBySide,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            Icons.vertical_split,
            size: 14,
            color: split ? palette.accentCurrent : palette.fg3,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Renderer** — in `diff_line_row.dart`: `HunkLines.build` watches `diffViewModeProvider`; when sideBySide returns `SplitHunkLines(...)`. Add:

```dart
/// Side-by-side rendering of a hunk: two half-width columns (old | new),
/// blank where a row has no counterpart. Reuses the same palette tints as
/// the unified rows.
class SplitHunkLines extends StatelessWidget {
  const SplitHunkLines({
    required this.lines,
    super.key,
    this.language,
    this.gutterWidth = 40,
  });
  final List<DiffLine> lines;
  final String? language;
  final double gutterWidth;

  @override
  Widget build(BuildContext context) {
    final rows = buildSplitRows(lines);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in rows)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _SplitCell(
                    line: r.left,
                    old: true,
                    language: language,
                    gutterWidth: gutterWidth,
                  ),
                ),
                Container(width: 1, color: AppPalette.of(context).border),
                Expanded(
                  child: _SplitCell(
                    line: r.right,
                    old: false,
                    language: language,
                    gutterWidth: gutterWidth,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SplitCell extends StatelessWidget {
  const _SplitCell({
    required this.line,
    required this.old,
    required this.language,
    required this.gutterWidth,
  });
  final DiffLine? line;
  final bool old;
  final String? language;
  final double gutterWidth;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l = line;
    if (l == null) return ColoredBox(color: palette.bg2.withValues(alpha: 0.4));
    final bg = switch (l.kind) {
      DiffLineKind.addition => palette.accentCurrent.withValues(alpha: 0.10),
      DiffLineKind.deletion => palette.accentErr.withValues(alpha: 0.12),
      DiffLineKind.context => Colors.transparent,
    };
    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: gutterWidth,
            child: Text(
              (old ? l.oldLine : l.newLine)?.toString() ?? '',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: palette.fg3,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: buildHighlightedSpans(
                  l.content,
                  language,
                  baseColor: palette.fg0,
                ),
              ),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              softWrap: false,
              overflow: TextOverflow.clip,
            ),
          ),
        ],
      ),
    );
  }
}
```

`HunkLines.build` head becomes:

```dart
    final mode = ref.watch(diffViewModeProvider);
    if (mode == DiffViewMode.sideBySide) {
      return SplitHunkLines(
        lines: lines,
        language: language,
        gutterWidth: gutterWidth,
      );
    }
```

Add `SplitDiffToggle()` next to each `WordDiffToggle()` callsite (diff_view header row, `DiffHeader` in diff_preview_pane).

- [ ] **Step 5: Run split test + analyze. Commit** `feat(phase4): side-by-side diff mode`

---

### Task 4: Ignore-whitespace (commit diff view only)

**Files:** Modify `lib/application/git/git_read_operations.dart`, `lib/infrastructure/git/git_cli_file_reader.dart`, `lib/infrastructure/git/git_cli_read_operations.dart`, `lib/ui/common/diff_prefs.dart`, `lib/ui/bottom_panel/diff_view.dart`; Test infra diff test

- [ ] **Step 1: Failing infra test** (in `git_cli_read_operations_diff_test.dart`) — fixture: commit changing only indentation; `-w` yields no hunks:

```dart
    test('ignoreWhitespace drops whitespace-only changes', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        await File(p.join(f.path, 'file_0.txt'))
            .writeAsString('  content 0\n'); // indentation-only change
        await Process.run('git', ['add', '-A'], workingDirectory: f.path);
        await Process.run(
          'git',
          ['commit', '-q', '-m', 'indent'],
          workingDirectory: f.path,
        );
        final head = await Process.run(
          'git',
          ['rev-parse', 'HEAD'],
          workingDirectory: f.path,
        );
        final sut = GitCliReadOperations();
        final spec =
            DiffSpecCommitVsParent(CommitSha(head.stdout.toString().trim()));
        final normal = await sut.getDiff(loc(f), spec);
        expect(normal.files.single.hunks, isNotEmpty);
        final ws = await sut.getDiff(loc(f), spec, ignoreWhitespace: true);
        expect(
          ws.files.isEmpty || ws.files.single.hunks.isEmpty,
          isTrue,
        );
      } finally { await f.dispose(); }
    });
```

(needs `dart:io` + `package:path` imports in that test file if absent.)

- [ ] **Step 2: Implement** — interface: `getDiff(RepoLocation repo, DiffSpec spec, {bool ignoreWhitespace = false})`, same param on `getDiffForFile`. File reader `getDiff` gains the param; append `if (ignoreWhitespace) '-w'` right after the existing per-spec args (before the `--` path filter). Facade passes through both. Doc note on the interface: working-copy staging flows MUST keep the default (patches must match the index byte-for-byte).
- [ ] **Step 3: UI** — in `diff_prefs.dart`:

```dart
/// Whether the COMMIT diff view passes `-w` to git. Deliberately not applied
/// to the working-copy preview: its hunks feed buildPatchForHunks and must
/// match the index byte-for-byte. Session-scoped.
final ignoreWhitespaceProvider = StateProvider<bool>((_) => false);

/// Toggle for [ignoreWhitespaceProvider], shown in the commit diff header.
class IgnoreWhitespaceToggle extends ConsumerWidget {
  const IgnoreWhitespaceToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final enabled = ref.watch(ignoreWhitespaceProvider);
    return Tooltip(
      message: enabled
          ? 'Whitespace ignored (-w) — click to include'
          : 'Whitespace shown — click to ignore (-w)',
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        borderRadius: BorderRadius.circular(3),
        onTap: () =>
            ref.read(ignoreWhitespaceProvider.notifier).state = !enabled,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            Icons.space_bar,
            size: 14,
            color: enabled ? palette.accentCurrent : palette.fg3,
          ),
        ),
      ),
    );
  }
}
```

`diff_view.dart`: `_diffProvider`/`_fullFileProvider` keys gain `bool ignoreWs` (record field) and pass it to getDiff/getDiffForFile; `DiffView.build` reads `ref.watch(ignoreWhitespaceProvider)` into the key; header row adds `IgnoreWhitespaceToggle()` before `SplitDiffToggle()`.

- [ ] **Step 4: Run infra diff tests + analyze. Commit** `feat(phase4): ignore-whitespace toggle for the commit diff view`

---

### Task 5: Finalize S3

- [ ] Bump `pubspec.yaml` → `0.1.15+16`; full suite `-j 2` green; analyze clean.
- [ ] Push, PR (summary + spec link), watch checks, merge on green (CD v0.1.15).
