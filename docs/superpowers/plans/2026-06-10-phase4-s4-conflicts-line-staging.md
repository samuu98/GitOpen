# Phase 4 — S4 Conflicts + Line-Level Staging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-file "Take ours/theirs" in the conflict panel; line-level staging and per-hunk discard in the working copy.

**Architecture:** `takeConflictSide` is a worktree-writer op (`git checkout --ours|--theirs -- <path>` + stage) surfaced through service/controller. Line staging is a pure `buildPatchForLines` next to `buildPatchForHunks`: unselected deletions become context, unselected additions are dropped, the hunk header is recomputed; the existing `stagePatch` applies it. Per-hunk discard is a new `discardPatch` write op (`git apply --reverse` on the working tree, no `--cached`) behind a confirm dialog.

**Tech Stack:** Flutter/Dart, riverpod; real-git fixtures.

**Branch:** `feat/phase4-s4-conflicts-staging` from main (after S3 merges). Version → `0.1.16+17`.

**Commands** (from `D:\repos\Personal\GitOpen`): test/analyze via `& "C:\Users\g.chirico\flutter\bin\flutter.bat" …`; full suite with `-j 2`. No blanket `dart format`.

## File Structure

| File | Change |
|---|---|
| `lib/application/git/git_write_operations.dart` | + `takeConflictSide`, `discardPatch` |
| `lib/infrastructure/git/git_cli_worktree_writer.dart` | impls |
| `lib/infrastructure/git/git_cli_write_operations.dart` | delegations |
| `lib/application/git/git_actions_service.dart` | + `takeConflictSide`, `discardHunk` |
| `lib/ui/git/git_actions_controller.dart` | wrappers |
| `lib/ui/conflicts/conflict_resolution_panel.dart:81-102` | + Ours/Theirs buttons |
| `lib/application/diff/build_patch_for_lines.dart` | NEW pure builder |
| `lib/ui/working_copy/file_row.dart` | line selection + stage-lines + discard-hunk |
| tests | infra ours/theirs + discardPatch; pure builder; service mapping |

---

### Task 1: Backend — `takeConflictSide` + `discardPatch` (TDD)

**Files:** Modify the four chain files; Test `test/infrastructure/git/git_cli_write_operations_conflict_side_test.dart` (new), `test/application/git/git_actions_service_local_test.dart`

- [ ] **Step 1: Failing infra test**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;

import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) => RepoLocation(RepoId.newId(), f.path, 't');

  /// master and feature both edit line 1 of clash.txt → merging feature
  /// into master conflicts.
  Future<RepoFixture> conflictFixture() async {
    final f = await RepoFixture.empty();
    Future<void> git(List<String> args) async {
      final r = await Process.run('git', args, workingDirectory: f.path);
      // merge is EXPECTED to exit non-zero on conflict; everything else must
      // succeed.
      if (args.first != 'merge') {
        expect(r.exitCode, 0, reason: '${args.join(' ')}: ${r.stderr}');
      }
    }

    final file = File(p.join(f.path, 'clash.txt'));
    await file.writeAsString('base\n');
    await git(['add', 'clash.txt']);
    await git(['commit', '-q', '-m', 'base']);
    await git(['checkout', '-q', '-b', 'feature']);
    await file.writeAsString('theirs\n');
    await git(['add', 'clash.txt']);
    await git(['commit', '-q', '-m', 'feature edit']);
    await git(['checkout', '-q', 'master']);
    await file.writeAsString('ours\n');
    await git(['add', 'clash.txt']);
    await git(['commit', '-q', '-m', 'master edit']);
    await git(['merge', 'feature']); // conflicts
    return f;
  }

  group('takeConflictSide', () {
    test('ours keeps our content and stages the file', () async {
      final f = await conflictFixture();
      try {
        final sut = GitCliWriteOperations();
        final res =
            await sut.takeConflictSide(loc(f), 'clash.txt', ours: true);
        expect(res, isA<GitSuccess<void>>());
        final content =
            await File(p.join(f.path, 'clash.txt')).readAsString();
        expect(content.trim(), 'ours');
        final status = await Process.run(
          'git',
          ['status', '--porcelain'],
          workingDirectory: f.path,
        );
        expect(status.stdout.toString(), isNot(contains('UU clash.txt')));
      } finally {
        await f.dispose();
      }
    });

    test('theirs takes the incoming content', () async {
      final f = await conflictFixture();
      try {
        final sut = GitCliWriteOperations();
        final res =
            await sut.takeConflictSide(loc(f), 'clash.txt', ours: false);
        expect(res, isA<GitSuccess<void>>());
        final content =
            await File(p.join(f.path, 'clash.txt')).readAsString();
        expect(content.trim(), 'theirs');
      } finally {
        await f.dispose();
      }
    });
  });

  group('discardPatch', () {
    test('reverses a working-tree change', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        await File(p.join(f.path, 'file_0.txt'))
            .writeAsString('content 0\nextra\n');
        final diff = await Process.run(
          'git',
          ['diff'],
          workingDirectory: f.path,
        );
        final sut = GitCliWriteOperations();
        final res =
            await sut.discardPatch(loc(f), diff.stdout.toString());
        expect(res, isA<GitSuccess<void>>());
        final content =
            await File(p.join(f.path, 'file_0.txt')).readAsString();
        expect(content, 'content 0\n');
      } finally {
        await f.dispose();
      }
    });
  });
}
```

- [ ] **Step 2: Implement** — interface (`git_write_operations.dart`, after `cleanUntracked`):

```dart
  /// Resolves a conflicted [path] wholesale: `git checkout --ours|--theirs
  /// -- <path>` followed by staging it (mark resolved).
  Future<GitResult<void>> takeConflictSide(
    RepoLocation r,
    String path, {
    required bool ours,
  });

  /// Reverses [unifiedDiff] in the WORKING TREE (`git apply --reverse`, no
  /// `--cached`) — backs per-hunk discard.
  Future<GitResult<void>> discardPatch(RepoLocation r, String unifiedDiff);
```

Worktree writer (next to `stagePatch`):

```dart
  Future<GitResult<void>> takeConflictSide(
    RepoLocation r,
    String path, {
    required bool ours,
  }) async {
    final side = ours ? '--ours' : '--theirs';
    final checkout = await _git.runVoid(r, ['checkout', side, '--', path]);
    if (checkout is GitFailure<void>) return checkout;
    return stageFiles(r, [path]);
  }

  Future<GitResult<void>> discardPatch(RepoLocation r, String unifiedDiff) =>
      _applyPatch(
          r, ['apply', '--reverse', '--whitespace=nowarn', '-'], unifiedDiff);
```

Facade: two one-line delegations. Service (after `stashDrop`):

```dart
  /// Resolves a conflicted file by taking one side wholesale.
  Future<ActionResult> takeConflictSide(
    RepoLocation repo,
    String path, {
    required bool ours,
  }) =>
      _simple(
        'Resolve',
        _write.takeConflictSide(repo, path, ours: ours),
        invalidate: _localScope,
      );

  /// Discards the hunks in [patch] from the working tree.
  Future<ActionResult> discardHunk(RepoLocation repo, String patch) =>
      _simple('Discard', _write.discardPatch(repo, patch));
```

Controller: `_runLocal` wrappers `takeConflictSide(context, repo, path, {required bool ours})` and `discardHunk(context, repo, patch)`.

- [ ] **Step 3: Service-mapping test** in `git_actions_service_local_test.dart`: fake overrides returning `voidResult` + one failure-message test (`'Resolve failed:'`). Run infra + service tests — PASS. **Commit** `feat(phase4): takeConflictSide + discardPatch write ops through the facade`

---

### Task 2: Conflict panel Ours/Theirs buttons

**Files:** Modify `lib/ui/conflicts/conflict_resolution_panel.dart:81-102`

- [ ] **Step 1:** In each file's trailing `Row`, before 'Resolve':

```dart
                            TextButton(
                              onPressed: () async {
                                await ref
                                    .read(gitActionsControllerProvider)
                                    .takeConflictSide(context, repo, path,
                                        ours: true);
                                ref.invalidate(_conflictsProvider(repo));
                              },
                              child: const Text('Ours'),
                            ),
                            TextButton(
                              onPressed: () async {
                                await ref
                                    .read(gitActionsControllerProvider)
                                    .takeConflictSide(context, repo, path,
                                        ours: false);
                                ref.invalidate(_conflictsProvider(repo));
                              },
                              child: const Text('Theirs'),
                            ),
```

- [ ] **Step 2: analyze clean. Commit** `feat(phase4): take ours/theirs per file in the conflict panel`

---

### Task 3: `buildPatchForLines` (pure, TDD)

**Files:** Create `lib/application/diff/build_patch_for_lines.dart`; Test `test/application/diff/build_patch_for_lines_test.dart`

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/diff/build_patch_for_lines.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';

void main() {
  // old: a,b   new: a,X,c  → hunk: ' a', '-b', '+X', '+c'
  final hunk = DiffHunk(
    oldStart: 1,
    oldCount: 2,
    newStart: 1,
    newCount: 3,
    header: '@@ -1,2 +1,3 @@',
    lines: const [
      DiffLine(kind: DiffLineKind.context, content: 'a', oldLine: 1, newLine: 1),
      DiffLine(kind: DiffLineKind.deletion, content: 'b', oldLine: 2),
      DiffLine(kind: DiffLineKind.addition, content: 'X', newLine: 2),
      DiffLine(kind: DiffLineKind.addition, content: 'c', newLine: 3),
    ],
  );

  test('selecting all lines reproduces the whole hunk', () {
    final patch = buildPatchForLines('f.txt', hunk, {1, 2, 3});
    expect(patch, contains('@@ -1,2 +1,3 @@'));
    expect(patch, contains('-b'));
    expect(patch, contains('+X'));
    expect(patch, contains('+c'));
  });

  test('unselected addition is dropped and counts recomputed', () {
    final patch = buildPatchForLines('f.txt', hunk, {1, 2});
    expect(patch, contains('@@ -1,2 +1,2 @@'));
    expect(patch, contains('-b'));
    expect(patch, contains('+X'));
    expect(patch, isNot(contains('+c')));
  });

  test('unselected deletion becomes context', () {
    final patch = buildPatchForLines('f.txt', hunk, {2, 3});
    expect(patch, contains('@@ -1,2 +1,4 @@'));
    expect(patch, contains(' b'));
    expect(patch, isNot(contains('-b')));
  });

  test('no selected changes yields empty string', () {
    expect(buildPatchForLines('f.txt', hunk, <int>{}), isEmpty);
  });
}
```

- [ ] **Step 2: Implement**

```dart
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';

/// Builds a unified-diff patch applying only the hunk lines whose indexes
/// (into [hunk].lines) are in [selected]:
/// - unselected deletions stay in the file → emitted as context;
/// - unselected additions don't enter the file → omitted;
/// - counts in the header are recomputed accordingly.
/// Returns '' when the selection contains no +/- line (nothing to apply).
String buildPatchForLines(
  String filePath,
  DiffHunk hunk,
  Set<int> selected,
) {
  final body = StringBuffer();
  var oldCount = 0;
  var newCount = 0;
  var changes = 0;
  for (final (i, line) in hunk.lines.indexed) {
    switch (line.kind) {
      case DiffLineKind.context:
        body.writeln(' ${line.content}');
        oldCount++;
        newCount++;
      case DiffLineKind.deletion:
        if (selected.contains(i)) {
          body.writeln('-${line.content}');
          oldCount++;
          changes++;
        } else {
          body.writeln(' ${line.content}');
          oldCount++;
          newCount++;
        }
      case DiffLineKind.addition:
        if (selected.contains(i)) {
          body.writeln('+${line.content}');
          newCount++;
          changes++;
        }
    }
  }
  if (changes == 0) return '';
  final buf = StringBuffer()
    ..writeln('diff --git a/$filePath b/$filePath')
    ..writeln('--- a/$filePath')
    ..writeln('+++ b/$filePath')
    ..writeln('@@ -${hunk.oldStart},$oldCount +${hunk.newStart},$newCount @@')
    ..write(body);
  return buf.toString();
}
```

- [ ] **Step 3: PASS + integration sanity** — add one real-git test to the conflict-side test file (or a new one): modify two lines in a committed file, build a patch selecting only one change via `buildPatchForLines` on the parsed hunk from `getDiff`, `stagePatch` it, assert `git diff --cached` contains only that change.
- [ ] **Step 4: Commit** `feat(phase4): buildPatchForLines — line-granular patch builder`

---

### Task 4: FileRow line selection + per-hunk discard

**Files:** Modify `lib/ui/working_copy/file_row.dart` (hunk section, around `_checkedHunks`/`_stageSelectedHunks`)

- [ ] **Step 1:** Add state `final Map<int, Set<int>> _checkedLines = {};` (hunk index → selected line indexes; cleared with `_checkedHunks` in `_toggleExpanded`). In the hunk section (locate `_buildHunkSection` — it renders each hunk with a checkbox; follow its existing structure):
  - each rendered diff line gets a leading 14 px checkbox (`Icons.check_box`/`_outline_blank`, only for +/- lines) toggling `_checkedLines[hunkIndex]`;
  - per-hunk trailing actions get a small 'Discard hunk' icon button (`Icons.undo`) → confirm dialog → `controller.discardHunk(context, repo, buildPatchForHunks(path, [hunk]))` → invalidate `workingCopyStatusProvider` + `unstagedFileDiffProvider`;
  - when any `_checkedLines` non-empty, the header button becomes 'Stage selected lines' calling:

```dart
  Future<void> _stageSelectedLines(List<DiffHunk> allHunks) async {
    final patches = <String>[];
    for (final MapEntry(key: h, value: lines) in _checkedLines.entries) {
      if (lines.isEmpty) continue;
      final patch =
          buildPatchForLines(widget.entry.path, allHunks[h], lines);
      if (patch.isNotEmpty) patches.add(patch);
    }
    if (patches.isEmpty) return;
    final write = ref.read(gitWriteOperationsProvider);
    for (final patch in patches) {
      await write.stagePatch(widget.repo, patch);
    }
    setState(_checkedLines.clear);
    ref.invalidate(workingCopyStatusProvider(widget.repo));
  }
```

(Adapt to the actual `_buildHunkSection` widget structure read at execution time; keep `_checkedHunks` hunk-level flow working unchanged.)

- [ ] **Step 2: analyze + working-copy test files PASS. Commit** `feat(phase4): line-level staging + per-hunk discard in the working copy`

---

### Task 5: Finalize S4

- [ ] Bump `0.1.16+17`; full suite `-j 2`; analyze; push `feat/phase4-s4-conflicts-staging`; PR; merge on green (CD v0.1.16).
