# Split Large UI Files — Design

**Date:** 2026-06-17
**Status:** approved
**Owner:** zN3utr4l

## Context

Two UI files have grown past a comfortable size and bundle multiple
responsibilities:

- `lib/ui/working_copy/file_row.dart` (897 lines) — the working-copy file row
  `FileRow`/`_FileRowState` (~561 lines: selection state, dialogs, build, **and**
  all the stage/unstage/discard git actions), plus `HunkRow` + `_HunkLineRow`
  (expandable hunk/line widgets), `StateBadge`, `DiscardIconButton`, and a
  `_workingStateLabel` helper.
- `lib/ui/commit_graph/commit_graph_panel.dart` (833 lines) — the data layer
  (`GraphData`, `graphLimitProvider` *(currently the private `_graphLimitProvider`)*,
  `commitGraphDataProvider`, `_layoutInIsolate`) **and** the widget
  `CommitGraphPanel`/`_CommitGraphPanelState` (~567 lines: search field, list,
  pagination, lane rendering).

The codebase already separates provider layers from widgets elsewhere
(`working_copy_providers.dart`), so these two files are the outliers.

## Goal

Split both files into focused, single-responsibility units with **zero behaviour
change**. Each new unit is independently understandable; the existing test suite
and `flutter analyze` are the safety net.

## Scope decision (owner, 2026-06-17)

Approach **B (deeper extraction)**, delivered as **one branch / one PR**
(`refactor/split-large-ui-files`, release **v1.1.2**). Beyond moving the
self-contained widgets, also extract `_FileRowState`'s git-action logic into a
controller and the graph's search field into its own widget.

### Non-goals (YAGNI)

- No change to git ops, patch builders, providers' behaviour, or the
  auto-refresh wiring (only `commitGraphDataProvider`'s *location* moves).
- No new features; no visual change.
- The commit-graph **row** stays as-is (`commit_row.dart` already exists);
  lane painting and the `ListView`/scroll stay in the panel.
- Selection state, dialogs (confirm/prompt), and `setState` stay in the widget —
  only the git-performing logic moves to the controller.

## Design

### Sub-effort 1 — `file_row.dart`

**New files (all under `lib/ui/working_copy/`):**

1. `hunk_row.dart` ← `HunkRow` + `_HunkLineRow` (verbatim move). No external
   importers; only `file_row.dart` uses them → it adds the import.
2. `state_badge.dart` ← `StateBadge` + `DiscardIconButton` (verbatim move).
   `_workingStateLabel` stays in `file_row.dart` (only `_FileRowState.build`
   uses it, for the semantics label).
3. `file_row_actions.dart` ← `FileRowActions` — a thin controller constructed
   with a `WidgetRef` (`FileRowActions(this._ref)`), holding the git-performing
   logic lifted 1:1 from `_FileRowState`. Each method keeps the **exact** git op
   + invalidation it has today (some use `gitWriteOperationsProvider` +
   `_invalidateDiffs`, `_discardSelectedLines` uses `gitActionsControllerProvider`
   — preserved per-method):
   - `Future<void> toggleStage(RepoLocation repo, WorkingFileEntry entry, {required bool isStaged})`
   - `Future<void> stash(RepoLocation repo, String path, String message)`
   - `Future<void> discardFile(RepoLocation repo, WorkingFileEntry entry)`
   - `Future<void> stageHunks(RepoLocation repo, String path, List<DiffHunk> hunks)`
   - `Future<void> unstageHunks(RepoLocation repo, String path, List<DiffHunk> hunks)`
   - `Future<void> discardHunks(RepoLocation repo, String path, List<DiffHunk> hunks, {required bool isUntracked})`
   - `Future<void> stageLines(RepoLocation repo, String path, List<LineSelection> sel)`
   - `Future<void> unstageLines(RepoLocation repo, String path, List<LineSelection> sel)`
   - `Future<void> discardLines(RepoLocation repo, String path, List<LineSelection> sel)`
   - where `LineSelection` = `({DiffHunk hunk, Set<int> lines})` (a small record;
     replaces the in-widget `_patchesForCheckedLines` mapping, which moves here).
   - The invalidation helper (`_invalidateDiffs` — the providers it invalidates)
     moves into the controller as a private method, called by each action.

   **`file_row.dart` keeps** `FileRow`/`_FileRowState` with its selection state
   (`_checkedHunks`, `_checkedLines`, `_expanded`, `_hover`), `build`, the
   confirm/prompt dialogs, `_toggleExpanded/_toggleHunk/_toggleLine`, and
   `_workingStateLabel`. Its action methods become one-liners that build the
   `LineSelection` list from `_checkedLines` and call `FileRowActions`, then
   `setState` to clear the selection (selection clearing stays in the widget).
   `FileRowActions` is instantiated once (`late final _actions = FileRowActions(ref)`).

After: `file_row.dart` ≈ rendering + selection only; ~400 lines.

### Sub-effort 2 — `commit_graph_panel.dart`

**New files (under `lib/ui/commit_graph/`):**

1. `commit_graph_providers.dart` ← `GraphData`, `graphLimitProvider` (the
   private `_graphLimitProvider` renamed public — the widget writes it for
   pagination, line ~295), `commitGraphDataProvider`, `_layoutInIsolate`, and
   any provider-only privates it uses (`_gitLogTimeout`). Verbatim move +
   the rename. Mirrors `working_copy_providers.dart`.
2. `commit_graph_search_field.dart` ← the search field currently built by
   `_buildSearchField(context, palette)` → a `CommitGraphSearchField` widget
   (`ConsumerWidget`) reading/writing `commitSearchProvider` exactly as today.
3. `commit_graph_panel.dart` keeps `CommitGraphPanel`/`_CommitGraphPanelState`
   (the `ListView`, lane rendering, scroll/pagination), importing the providers
   file and the search-field widget.

**Importer ripple:** `lib/ui/auto_refresh/repo_auto_refresh_scope.dart` imports
`commitGraphDataProvider` from `commit_graph_panel.dart`; update it to import
`commit_graph_providers.dart`. (Grep confirms it is the only external importer.)

## Files

- **Add:** `lib/ui/working_copy/hunk_row.dart`, `.../state_badge.dart`,
  `.../file_row_actions.dart`; `lib/ui/commit_graph/commit_graph_providers.dart`,
  `.../commit_graph_search_field.dart`.
- **Modify:** `lib/ui/working_copy/file_row.dart` (extract; delegate to controller),
  `lib/ui/commit_graph/commit_graph_panel.dart` (extract; import providers +
  search field), `lib/ui/auto_refresh/repo_auto_refresh_scope.dart` (import path),
  `pubspec.yaml` (1.1.1 → 1.1.2), `CHANGELOG.md`.
- Any other file importing `HunkRow`/`StateBadge`/`commitGraphDataProvider` —
  grep shows none for the widgets; only `repo_auto_refresh_scope.dart` for the
  provider.

## Testing / verification

This is a behaviour-preserving refactor, so the guard is the **existing suite**:

- `flutter analyze` clean (catches broken imports / unused / lints).
- `flutter test` fully green — the existing working-copy widget tests
  (`file_list_widget_test.dart`, etc.) exercise stage/unstage/discard flows
  through `FileRow`, and the commit-graph tests exercise the panel; both must
  stay green, proving the extraction changed nothing observable.
- A focused unit test for `FileRowActions` is **out of scope** — its methods are
  thin wrappers over already-tested helpers (`buildPatchForHunks/Lines`, write
  ops) and are covered transitively by the widget tests; adding one would need a
  real git fixture for little marginal value (revisit if a method grows logic).
- Each extraction is its own commit (hunk_row, state_badge, file_row_actions,
  graph providers, graph search field), so a regression bisects to one move.
- Manual smoke optional (no behaviour change): stage/unstage/discard a hunk and
  a line; scroll the graph to grow the page; search.

## Risks / notes

- **Behaviour drift in the controller extraction** is the one real risk — each
  `FileRowActions` method must keep its exact git op + invalidation (they are not
  uniform: most use `gitWriteOperationsProvider` + the diff-invalidation helper,
  `_discardSelectedLines` uses `gitActionsControllerProvider`). Mitigation: move
  per-method, run the working-copy widget tests after each.
- **`graphLimitProvider` rename** is the only public-surface change; the widget
  and (after the import fix) nothing else references it. `commitGraphDataProvider`
  keeps its name; only its file moves — the one importer
  (`repo_auto_refresh_scope.dart`) is updated in the same task.
- Drift codegen unaffected (no schema/table change); `database.g.dart` stays as
  regenerated.
