# Split Large UI Files Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `file_row.dart` (897) and `commit_graph_panel.dart` (833) into focused single-responsibility files, with zero behaviour change.

**Architecture:** Behaviour-preserving extraction (Approach B). Move the self-contained widgets to their own files; lift `_FileRowState`'s git-action logic into a `FileRowActions` controller (selection/dialogs stay in the widget); move the graph data layer to `commit_graph_providers.dart` and the search field to its own widget. No logic changes.

**Tech Stack:** Flutter, Riverpod, `flutter_test`. No new dependencies.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-06-17-split-large-ui-files-design.md`.
- **Zero behaviour change.** The guard is the existing suite + analyzer — NOT new tests. Each task ends green.
- `very_good_analysis` strict; `flutter analyze` must be clean (info lints fail it). Wrap ~80 cols.
- `database.g.dart` is gitignored/regenerated — no schema change here, leave it.
- One branch `refactor/split-large-ui-files`; release **v1.1.2**. Git identity `zN3utr4l`; `gh` flips to giuseppe-chirico — re-`gh auth switch` before any push/merge.
- Moves are **verbatim**: cut the named symbols unchanged; only fix `import`s (the analyzer lists missing/unused). Do not rewrite logic.
- After each task: `flutter analyze <touched dirs>` clean **and** the affected test suite green, then commit. A regression must bisect to one task.

---

### Task 1: Extract `hunk_row.dart`

**Files:**
- Create: `lib/ui/working_copy/hunk_row.dart`
- Modify: `lib/ui/working_copy/file_row.dart`

**Interfaces:**
- Produces: `HunkRow` (public widget) and the private `_HunkLineRow` it uses, unchanged.
- Consumes: nothing new (verbatim move).

- [ ] **Step 1: Move the widgets**

Cut `class HunkRow extends StatelessWidget { … }` (currently `file_row.dart:653`) and `class _HunkLineRow extends StatelessWidget { … }` (`file_row.dart:762`) — through the end of `_HunkLineRow` (just before `class StateBadge` at 851) — into a new `hunk_row.dart`. Add the imports those two classes reference (seed: `package:flutter/material.dart`, `package:flutter_riverpod/flutter_riverpod.dart` if used, `package:gitopen/domain/diff/diff_hunk.dart`, `package:gitopen/domain/diff/diff_line.dart`, `package:gitopen/ui/common/diff_line_row.dart`, `package:gitopen/ui/common/diff_syntax.dart`, `package:gitopen/ui/common/diff_prefs.dart`, `package:gitopen/ui/theme/app_palette.dart` — keep only what the analyzer says are used).

- [ ] **Step 2: Import + drop dead imports in `file_row.dart`**

Add `import 'package:gitopen/ui/working_copy/hunk_row.dart';` to `file_row.dart`. Remove any imports now unused there (the analyzer will flag them).

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/ui/working_copy`
Expected: No issues.

- [ ] **Step 4: Test the affected area**

Run: `flutter test test/ui/working_copy/`
Expected: All pass (unchanged behaviour).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/working_copy/hunk_row.dart lib/ui/working_copy/file_row.dart
git commit -m "refactor(working-copy): extract HunkRow into hunk_row.dart"
```

---

### Task 2: Extract `state_badge.dart`

**Files:**
- Create: `lib/ui/working_copy/state_badge.dart`
- Modify: `lib/ui/working_copy/file_row.dart`

**Interfaces:**
- Produces: `StateBadge`, `DiscardIconButton` (public widgets), unchanged.

- [ ] **Step 1: Move the widgets**

Cut `class DiscardIconButton extends StatelessWidget { … }` (`file_row.dart:628`) and `class StateBadge extends StatelessWidget { … }` (`file_row.dart:851`, to EOF) into a new `state_badge.dart`. Seed imports: `package:flutter/material.dart`, `package:gitopen/domain/status/working_file_entry.dart` (for `WorkingFileState`), `package:gitopen/ui/theme/app_palette.dart`. Keep `_workingStateLabel` in `file_row.dart` (only `_FileRowState.build` uses it). Trim to analyzer-used imports.

- [ ] **Step 2: Import in `file_row.dart`**

Add `import 'package:gitopen/ui/working_copy/state_badge.dart';`; drop now-unused imports.

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/ui/working_copy`
Expected: No issues.

- [ ] **Step 4: Test**

Run: `flutter test test/ui/working_copy/`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/working_copy/state_badge.dart lib/ui/working_copy/file_row.dart
git commit -m "refactor(working-copy): extract StateBadge/DiscardIconButton"
```

---

### Task 3: Extract `FileRowActions` controller

**Files:**
- Create: `lib/ui/working_copy/file_row_actions.dart`
- Modify: `lib/ui/working_copy/file_row.dart`

**Interfaces:**
- Produces: `FileRowActions` constructed with a `WidgetRef`:
  `FileRowActions(this._ref); final WidgetRef _ref;`
  Methods (each lifts the SAME git op + invalidation from the matching
  `_FileRowState` method; build patches via `buildPatchForHunks`/`buildPatchForLines`):
  - `Future<void> toggleStage(RepoLocation repo, WorkingFileEntry entry, {required bool isStaged})`
  - `Future<void> stash(RepoLocation repo, String path, String message)`
  - `Future<void> discardFile(RepoLocation repo, WorkingFileEntry entry)`
  - `Future<void> stageHunks(RepoLocation repo, String path, List<DiffHunk> hunks)`
  - `Future<void> unstageHunks(RepoLocation repo, String path, List<DiffHunk> hunks)`
  - `Future<void> discardHunks(RepoLocation repo, String path, List<DiffHunk> hunks, {required bool isUntracked})`
  - `Future<void> stageLines(RepoLocation repo, String path, List<LineSelection> sel)`
  - `Future<void> unstageLines(RepoLocation repo, String path, List<LineSelection> sel)`
  - `Future<void> discardLines(RepoLocation repo, String path, List<LineSelection> sel)`
  - record `typedef LineSelection = ({DiffHunk hunk, Set<int> lines});`
  - private `void _invalidateDiffs(RepoLocation repo)` — the exact set of
    `_ref.invalidate(...)` calls from the current `_FileRowState._invalidateDiffs`.
- Consumes (in the widget): keeps `_checkedHunks`/`_checkedLines`/`_expanded`,
  the dialogs, `_toggleExpanded/_toggleHunk/_toggleLine`, `_workingStateLabel`.

- [ ] **Step 1: Create the controller with the lifted bodies**

In `file_row_actions.dart`, define `FileRowActions(this._ref)` and move the git
logic from each `_FileRowState` action method **verbatim**, replacing
`widget.repo`/`widget.entry`/`widget.entry.path` with the method parameters and
`ref` with `_ref`. Source methods and their exact ops to preserve:
- `toggleStage` ← `_toggleStage` (stage vs unstage via `gitWriteOperationsProvider`; then `_ref.invalidate(workingCopyStatusProvider(repo))`).
- `stash` ← the git part of `_stashFile` (the `appPromptText` dialog stays in the widget; controller takes the resulting `message`).
- `discardFile` ← the git part of `_discard` (the `ConfirmDialog` stays in the widget; controller does the discard + invalidation).
- `stageHunks`/`unstageHunks` ← `_stageSelectedHunks`/`_unstageSelectedHunks` and `_unstageHunk` (drop the `setState(_checkedHunks.clear)` — that stays in the widget).
- `discardHunks` ← `_discardSelectedHunks` (keep its exact `gitWriteOperationsProvider`/`gitActionsControllerProvider` choice and `isUntracked` handling).
- `stageLines`/`unstageLines`/`discardLines` ← `_stageSelectedLines`/`_unstageSelectedLines`/`_discardSelectedLines`; move `_patchesForCheckedLines`'s patch-building here, parameterised by `List<LineSelection>` instead of reading `_checkedLines`. Preserve `_discardSelectedLines`'s use of `gitActionsControllerProvider` if that is what it uses today.
- `_invalidateDiffs` ← the current private helper's exact invalidate list.

Seed imports: `flutter_riverpod`, `providers.dart`, `git/git_actions_controller.dart` (if used), `application/diff/build_patch_for_hunks.dart`, `.../build_patch_for_lines.dart`, `domain/diff/diff_hunk.dart`, `domain/repositories/repo_location.dart`, `domain/status/working_file_entry.dart`.

- [ ] **Step 2: Rewire `_FileRowState` to delegate**

In `file_row.dart`: add `late final FileRowActions _actions = FileRowActions(ref);` and `import '.../file_row_actions.dart';`. Replace each action method's git body with a call to `_actions.<method>(...)`, keeping the surrounding dialog/selection/`setState` exactly as today. Examples:
- `_toggleStage` → `await _actions.toggleStage(widget.repo, widget.entry, isStaged: widget.isStaged);`
- `_stageSelectedHunks(all)` → build `hunks` list as today, `await _actions.stageHunks(widget.repo, widget.entry.path, hunks); setState(_checkedHunks.clear);`
- `_stageSelectedLines(all)` → build `List<LineSelection>` from `_checkedLines`, `await _actions.stageLines(widget.repo, widget.entry.path, sel); setState(_checkedLines.clear);`
- `_discard` → keep the `ConfirmDialog`, then `await _actions.discardFile(widget.repo, widget.entry);`
- `_stashFile` → keep `appPromptText`, then `await _actions.stash(widget.repo, widget.entry.path, msg);`
- same pattern for unstage/discard hunks & lines.
Remove `_patchesForCheckedLines` and `_invalidateDiffs` from the widget (now in the controller).

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/ui/working_copy`
Expected: No issues.

- [ ] **Step 4: Test the working-copy flows (behaviour guard)**

Run: `flutter test test/ui/working_copy/`
Expected: All pass — stage/unstage/discard at file/hunk/line still work identically.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/working_copy/file_row_actions.dart lib/ui/working_copy/file_row.dart
git commit -m "refactor(working-copy): lift FileRow git actions into FileRowActions"
```

---

### Task 4: Extract `commit_graph_providers.dart` (+ expose `graphLimitProvider`)

**Files:**
- Create: `lib/ui/commit_graph/commit_graph_providers.dart`
- Modify: `lib/ui/commit_graph/commit_graph_panel.dart`, `lib/ui/auto_refresh/repo_auto_refresh_scope.dart`

**Interfaces:**
- Produces (public): `GraphData`, `graphLimitProvider` (renamed from `_graphLimitProvider`), `commitGraphDataProvider`. Private `_layoutInIsolate` + any provider-only consts (`_gitLogTimeout`) move with them.

- [ ] **Step 1: Move the data layer**

Cut from `commit_graph_panel.dart` into `commit_graph_providers.dart`: `_layoutInIsolate` (39), the `_graphLimitProvider` declaration (58), `GraphData` (61), `commitGraphDataProvider` (76–265), and any provider-only privates they use (e.g. `_gitLogTimeout`). Rename `_graphLimitProvider` → `graphLimitProvider` (public) at its declaration and both uses (the provider body + the widget). Seed imports for the new file: `flutter_riverpod`, `flutter/foundation.dart` (for `compute`), `providers.dart`, `application/commit_graph/commit_node.dart`, `application/commit_graph/commit_graph_layout.dart` (if used), `application/commit_search_provider.dart`, `application/branch_visibility_provider.dart`, `domain/commits/commit_info.dart`, `domain/repositories/repo_location.dart`, plus whatever else `commitGraphDataProvider` references — analyzer-trimmed.

- [ ] **Step 2: Update the panel + the auto-refresh importer**

In `commit_graph_panel.dart`: add `import '.../commit_graph_providers.dart';`; change its `_graphLimitProvider` use (line ~295) to `graphLimitProvider`; drop imports now unused. In `lib/ui/auto_refresh/repo_auto_refresh_scope.dart`: change `import 'package:gitopen/ui/commit_graph/commit_graph_panel.dart';` → `import 'package:gitopen/ui/commit_graph/commit_graph_providers.dart';` (it only needs `commitGraphDataProvider`).

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/ui/commit_graph lib/ui/auto_refresh`
Expected: No issues.

- [ ] **Step 4: Test affected areas**

Run: `flutter test test/ui/commit_graph/ test/ui/auto_refresh/`
Expected: All pass (the auto-refresh test references `commitGraphDataProvider` — update its import to the new file too if it imports from the panel; analyzer/test will flag).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/commit_graph/commit_graph_providers.dart lib/ui/commit_graph/commit_graph_panel.dart lib/ui/auto_refresh/repo_auto_refresh_scope.dart test/ui/auto_refresh/repo_auto_refresh_scope_test.dart
git commit -m "refactor(graph): move data layer to commit_graph_providers.dart"
```

---

### Task 5: Extract `commit_graph_search_field.dart`

**Files:**
- Create: `lib/ui/commit_graph/commit_graph_search_field.dart`
- Modify: `lib/ui/commit_graph/commit_graph_panel.dart`

**Interfaces:**
- Produces: `CommitGraphSearchField` (`ConsumerWidget` or `ConsumerStatefulWidget` matching the current field's needs — if `_buildSearchField` uses a `TextEditingController`/`FocusNode` held in `_CommitGraphPanelState`, make it `ConsumerStatefulWidget` owning them).

- [ ] **Step 1: Move the search field**

Read `_buildSearchField` (`commit_graph_panel.dart:469`) and any state it relies on (controller/focus node/`commitSearchProvider` reads/writes). Move it into `CommitGraphSearchField` in the new file, owning whatever controller/focus-node it needs (moved out of `_CommitGraphPanelState`). Behaviour identical (same `commitSearchProvider` updates, same debounce if any). Seed imports: `flutter/material.dart`, `flutter_riverpod`, `application/commit_search_provider.dart`, `ui/theme/app_palette.dart`.

- [ ] **Step 2: Use it in the panel**

In `commit_graph_panel.dart`: replace the `_buildSearchField(context, palette)` call (line ~366) with `const CommitGraphSearchField()` (or pass `palette`/repo if needed); remove `_buildSearchField` and any now-orphaned controller/focus fields it owned; add the import; drop unused imports.

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/ui/commit_graph`
Expected: No issues.

- [ ] **Step 4: Test**

Run: `flutter test test/ui/commit_graph/`
Expected: All pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/commit_graph/commit_graph_search_field.dart lib/ui/commit_graph/commit_graph_panel.dart
git commit -m "refactor(graph): extract CommitGraphSearchField"
```

---

### Task 6: Version bump + full verification

**Files:**
- Modify: `pubspec.yaml`, `CHANGELOG.md`

- [ ] **Step 1: Bump version**

`pubspec.yaml`: `1.1.1+39` → `1.1.2+40`.

- [ ] **Step 2: CHANGELOG entry**

Add at top:
```markdown
## [1.1.2] — 2026-06-17

### Changed
- Internal refactor: split the two largest UI files into focused units
  (`file_row.dart` → `hunk_row.dart` + `state_badge.dart` + a `FileRowActions`
  controller; `commit_graph_panel.dart` → `commit_graph_providers.dart` +
  `commit_graph_search_field.dart`). No user-facing change.
```

- [ ] **Step 3: Confirm the split landed**

Run: `wc -l lib/ui/working_copy/file_row.dart lib/ui/commit_graph/commit_graph_panel.dart`
Expected: both meaningfully smaller (file_row ≈ 400; panel ≈ 450–550).

- [ ] **Step 4: Full gate**

Run: `flutter analyze`
Expected: No issues.

Run: `flutter test`
Expected: All tests pass (the whole suite — proves zero behaviour change).

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml CHANGELOG.md
git commit -m "chore: bump to 1.1.2 for the UI-file split"
```

---

## Self-Review

**Spec coverage:**
- file_row → hunk_row.dart (T1), state_badge.dart (T2), FileRowActions (T3), slimmed file_row (T1–T3). ✓
- commit_graph_panel → commit_graph_providers.dart + expose graphLimitProvider (T4), commit_graph_search_field.dart (T5), slimmed panel (T4–T5). ✓
- Update `repo_auto_refresh_scope.dart` importer (T4). ✓
- One branch/PR, v1.1.2 (T6). ✓
- Guard = existing suite + analyze, each extraction its own commit (every task). ✓
- Non-goals respected: no logic change, commit row untouched, dialogs/selection stay in widget. ✓

**Placeholder scan:** The moves are specified by exact symbol + source line + seed import list, with "analyzer-trim imports" as the mechanical finish — this is the real process for a verbatim move, not a TODO. No "implement later". Task 3 lists each controller method's source method and the exact op to preserve (no logic invented).

**Type consistency:** `FileRowActions(WidgetRef)`, `LineSelection = ({DiffHunk hunk, Set<int> lines})`, the nine controller methods, `graphLimitProvider` (consistently renamed in T4 and used in T2-of-graph references), `commitGraphDataProvider` (name unchanged, file moved), `CommitGraphSearchField`, `HunkRow`/`StateBadge`/`DiscardIconButton` — names consistent across tasks. `commitGraphDataProvider` importer update (T4) matches the perf-branch import added in `repo_auto_refresh_scope.dart`.
