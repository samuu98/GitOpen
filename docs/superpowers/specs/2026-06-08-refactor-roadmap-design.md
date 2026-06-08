# Refactoring Roadmap

**Date:** 2026-06-08
**Status:** approved (execute slice by slice, one PR each)
**Owner:** zN3utr4l

## Context

Post Slice 0 (foundation) the codebase is lint-clean (very_good_analysis) and
~62% covered, but a four-agent architecture audit surfaced structural debt:
business/git orchestration duplicated across UI widgets, layering violations
(UI → infrastructure, application → UI/`dart:io`), two oversized infra god-files
(`git_cli_read_operations` 957, `git_cli_write_operations` 838) and UI god-files
(`sidebar` 1037, `working_copy_panel` 888, `git_toolbar` 849, `auth_dialog` 462),
plus dead code and a few correctness smells.

`main` is protected → every slice ships as its own PR (CI green required).
Structural refactors are **behaviour-preserving** (verified by the existing test
suite + `flutter analyze`); behaviour-affecting fixes (Slices 5–6) get dedicated
TDD.

## Slices (execution order 0 → 6)

### Slice 0 — Quick-wins & dead code (S, low risk)
- Remove the `repoStatusProvider` name collision: `lib/ui/commit_graph/local_changes_row.dart:11`
  redefines a public provider already in `lib/application/providers.dart:109`.
  Delete the UI-local one; have `LocalChangesRow` watch the application provider.
- Remove dead code: `Workspace.{selectedBranchFullName,selectedSha,scrollOffset}`
  (never read/written; selection lives in providers); `commitGraphLayoutProvider`
  (unused DI seam) + fix the now-misleading doc comment on `CommitGraphLayout`;
  `GitProcessRunner.streamLines` (unused); `CredentialHelper.setup`'s `host` param
  (always `''`).
- Fix coverage: the CI `lcov_cobertura --excludes` did not drop generated files
  (badge shows 52% instead of ~62%); correct the exclude so generated `*.g.dart`
  is omitted.

### Slice 1 — Git-actions facade + layering (L, highest leverage)
Application-layer service owning dialog → write-op → invalidate → snackbar/progress
**+ auth-retry**, consumed by sidebar, commit-graph, toolbar, `main`, conflict-panel.
Fixes the real bug (F5 fetch lacks the toolbar's auth-retry → silent failure) and the
layering violations (UI importing `GitProcessException`, `Process.run`/`http` in
widgets). Pulls in the shared helpers the audit flagged (`appPromptText`,
`revealCommit`, `activeWorkspaceProvider`, merge/rebase flow helpers).

### Slice 2 — Split infra git god-files (M, low risk)
`GitCliReadOperations`/`GitCliWriteOperations` become thin facades that still
`implements` their interfaces, delegating to per-concern collaborators. Add
`_runVoid`/`_runThenHead` helpers to collapse ~250 lines of `try/catch →
GitFailure(_classify(e)…)` boilerplate; dedupe conflict-list + process-capture.

### Slice 3 — Split UI god-widgets (M-L, low risk)
Split `sidebar`, `working_copy_panel`, `git_toolbar`, `auth_dialog` into focused
files; extract shared diff line/hunk widget (used 3×) and `AppIconButton` hover
button; move `buildPatchForHunks` to application. Includes the `auth_dialog`
device-flow state-machine extraction (and revisits the transient `polling` state).

### Slice 4 — Application purity / DI seams (M)
`AuthResolver`/`repoStateProvider` stop calling git/FS directly (inject ports);
add `ActivityLogStore`/`SettingsStore` interfaces; remove `dart:io` `Process` from
`OperationsNotifier` (abstract cancel); make `AuthSpec` `Equatable`; move
`folder_picker` behind an application port; relocate `auth_spec.dart` to `application/auth/`.

### Slice 5 — Unified error model (L)
Read ops currently throw `GitProcessException`; write ops return `GitResult`.
Unify so infrastructure exceptions never reach the UI (reads → `GitResult` or a
typed application error). TDD.

### Slice 6 — Correctness fixes (S each, TDD)
`getDiff` path-with-spaces; `getStatus` field-parse guards; `_classify`
false-positives (`auth` matching "author"); `_runProgressStream` stderr loss +
await drain; optional timeout on `GitProcessRunner.run`; device-flow polling
robustness. Each its own failing-test-first fix.

## Acceptance per slice
`flutter analyze` clean, `flutter test` green (behaviour preserved for 0–4),
CI green on the PR, merged to `main`.
