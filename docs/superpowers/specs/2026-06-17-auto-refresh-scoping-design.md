# Auto-Refresh Scoping — Design

**Date:** 2026-06-17
**Status:** approved
**Owner:** zN3utr4l

## Context

`RepoAutoRefreshScope` (`lib/ui/auto_refresh/repo_auto_refresh_scope.dart`)
keeps the active repo fresh. Today its `_refresh()` does a blanket
`ref.invalidate(gitReadOperationsProvider)` (+ `repoStateProvider`). Because
`gitReadOperationsProvider` is `ref.watch`-ed by **every** read provider, one
refresh re-runs the entire read layer:

- the commit graph `git log` (300 commits) — `_commitGraphDataProvider`
- local **and** remote branches — `localBranchesProvider` / `remoteBranchesProvider`
- the whole sidebar — `sidebarDataProvider` (branches + tags + remotes + stashes
  + submodules + worktrees, loaded atomically)
- working-tree status — `repoStatusProvider` / `workingCopyStatusProvider`
- the selected commit's details/diff — even though commit data is immutable

`_refresh()` fires on two triggers:

1. **Watcher** — `RepoWatcher.changes()` debounced 400 ms. The watcher watches
   `<gitdir>` and `<gitdir>/logs` non-recursively and filters `index` + `*.lock`
   as transient noise. The events that pass are genuine ref/HEAD/fetch/state
   changes.
2. **Focus regain** — `AppLifecycleListener.onResume` (gated by the `autoRefresh`
   setting).

The cost is invisible after the recent flicker fix (`skipLoadingOnReload`) but
real: on a large repo, alt-tabbing back re-logs the whole graph and re-reads
every ref every time.

Key observations that drive the design:

- `Directory.watch` is OS-level and fires **even while the window is
  unfocused**. So external `.git` mutations (commit/fetch/checkout) made while
  away are already caught by the watcher. The only thing focus-regain uniquely
  needs to catch is **working-tree edits** (an editor touching files does not
  write `.git`) — i.e. `status`/working-copy, **not** graph/branches.
- `RepoStatus` already carries `headSha`, so a focus refresh can detect a
  HEAD move for free (no extra git call) as a safety net against a missed
  watcher event.
- The blanket `invalidate(gitReadOperationsProvider)` is also used by git
  **write** paths (`git_actions_controller`, `commit_compose`) and the sidebar —
  those legitimately want a broad refresh and are **out of scope** here. Only the
  auto-refresh path over-refreshes. Working-copy actions already invalidate
  scoped (`workingCopyStatusProvider`).

## Goal

Cut redundant work on every fetch and especially every focus regain, while
preserving freshness. Concretely: a focus regain must not re-log the graph or
re-read refs unless HEAD actually moved; watcher events refresh only the scopes
the changed `.git` path can affect.

## Scope decisions (owner, 2026-06-17)

1. **Focus regain refreshes `worktree` + `state` only**, plus a `headSha`
   safety net that adds `refs` when HEAD moved since the last refresh.
2. **Scope the watcher too**: emit *what* changed and invalidate only the
   affected scopes.
3. **Approach A — scoped direct invalidation** (no revision tokens). Expose the
   graph provider; the auto-refresh path invalidates explicit public provider
   subsets. Write-path and working-copy invalidations are left unchanged.

### Non-goals (YAGNI)

- No change to git write paths / `commit_compose` / `git_actions_controller`
  (they correctly broad-refresh after a mutation).
- No splitting of `sidebarDataProvider` into per-section providers — it stays
  atomic; the `refs` scope refreshes the sidebar as a unit.
- No revision-token plumbing across every provider (Approach B, rejected).
- No new user-facing settings.

## Design

### Watcher change kinds

`RepoWatcher.changes(RepoLocation)` becomes `Stream<RepoChange>` (was
`Stream<void>`). `RepoChange` is an enum classified from the changed file's
basename / path, computed by a **pure** function `classifyGitChange(String path)
-> RepoChange?` (returns `null` for filtered noise):

| Path (basename / prefix)                              | `RepoChange` |
|-------------------------------------------------------|--------------|
| `HEAD`, `logs/HEAD`, `logs/…`                          | `head`       |
| `packed-refs`, anything under `refs/`                  | `refs`       |
| `FETCH_HEAD`, `ORIG_HEAD`                              | `fetch`      |
| `MERGE_HEAD`, `REVERT_HEAD`, `CHERRY_PICK_HEAD`, `rebase-merge/*`, `rebase-apply/*` | `mergeState` |
| `index`, `*.lock`                                     | `null` (filtered, as today) |
| anything else                                          | `null`       |

The debouncer collects the **set** of non-null kinds seen during the 400 ms
window and emits their union once (today it coalesces `void` events; now it
coalesces a `Set<RepoChange>`). `Debouncer` is extended (or wrapped) to carry
the accumulated set; the existing `lib/application/watch/debouncer.dart` time
behavior is unchanged.

### Refresh scopes and provider sets

A `RepoRefreshScope` enum: `worktree`, `refs`, `state`. A pure mapping
`scopesForChange(Set<RepoChange>) -> Set<RepoRefreshScope>`:

| `RepoChange` | scopes                          | rationale |
|--------------|---------------------------------|-----------|
| `head`       | `worktree` + `refs` + `state`   | checkout/commit moves HEAD and the tree |
| `refs`       | `refs` + `state`                | branch/tag create/delete; tree unchanged |
| `fetch`      | `refs` + `state`                | fetched commits/remote refs; tree untouched |
| `mergeState` | `worktree` + `state`            | conflicts/status; no new commit → no graph re-log |

A separate `scopesForFocus({required bool headMoved})`:
`{worktree, state}` plus `refs` when `headMoved`.

Provider sets per scope (invalidated by the auto-refresh scope):
- `worktree` → `repoStatusProvider(repo)`, `workingCopyStatusProvider(repo)`
- `refs` → `localBranchesProvider(repo)`, `remoteBranchesProvider(repo)`,
  `sidebarDataProvider(repo)`, `commitGraphDataProvider(repo)`
  (the branch **leaves** must be invalidated so `branchesProvider`,
  `sidebarDataProvider`, and the status-bar branch name actually re-fetch)
- `state` → `repoStateProvider(repo)`

### Exposing the graph provider

`_commitGraphDataProvider` (private in `commit_graph_panel.dart`) moves to a new
`lib/ui/commit_graph/commit_graph_providers.dart` as public
`commitGraphDataProvider` (+ its `_GraphData`/return type as needed), mirroring
`working_copy_providers.dart`. `commit_graph_panel.dart` imports it. This is the
only structural change and also tidies the 833-line panel slightly.

### Wiring in `RepoAutoRefreshScope`

- Subscribe to `repoWatcherProvider.changes(repo)` (now typed). On each debounced
  union set, compute `scopesForChange(...)` and invalidate the mapped providers.
  After a refresh that includes `refs`/`head`, record the new `headSha` (read
  from the refreshed `repoStatusProvider` value) as `_lastHeadSha`.
- `onResume`: if `autoRefresh` is on, invalidate `worktree` + `state`; then
  `ref.listen`/read `repoStatusProvider(repo)`'s next value — if `headSha !=
  _lastHeadSha`, invalidate `refs` and update `_lastHeadSha`. (Reading the
  already-refreshed status is free; the comparison is the safety net.)
- `_lastHeadSha` is seeded on first successful status load and updated on every
  refresh that reads status.

The existing `autoRefresh` setting still gates focus refresh; the debounced
watcher subscription is created/cancelled exactly as today.

## Files

- **Add:** `lib/application/watch/repo_change.dart` — `RepoChange` enum +
  `classifyGitChange`; `RepoRefreshScope` enum + `scopesForChange` /
  `scopesForFocus` (pure, no Flutter imports).
- **Add:** `lib/ui/commit_graph/commit_graph_providers.dart` — public
  `commitGraphDataProvider` (moved out of `commit_graph_panel.dart`).
- **Modify:** `lib/application/watch/repo_watcher.dart` (port:
  `Stream<RepoChange>`), `lib/infrastructure/watch/io_repo_watcher.dart`
  (classify + emit kinds), `lib/application/watch/debouncer.dart` (coalesce a
  set — or add a small `SetDebouncer`), `lib/ui/auto_refresh/repo_auto_refresh_scope.dart`
  (scoped invalidation + headSha safety net), `lib/ui/commit_graph/commit_graph_panel.dart`
  (import the moved provider).
- **Tests:** `test/application/watch/repo_change_test.dart` (classify + scope
  maps), update `test/infrastructure/watch/io_repo_watcher_test.dart` (emits
  typed kinds), update `test/ui/auto_refresh/repo_auto_refresh_scope_test.dart`
  (focus refreshes status not graph; watcher head→refs+worktree, mergeState→no
  graph).
- **Modify:** `pubspec.yaml` version bump + `CHANGELOG.md`.

## Error handling & edge cases

- **Missed watcher event** (path not classified, or OS dropped it): the focus
  `headSha` safety net catches a HEAD move; a pure ref change with no HEAD move
  and no focus event is the residual gap — acceptable and no worse than a single
  missed event today (the next `.git` write resyncs).
- **No status yet / detached HEAD**: `headSha` may be null; treat null≠null as
  "unknown → refresh refs" on the first focus to be safe, then settle.
- **Debounce window mixing kinds**: union of scopes is taken, so a burst that
  includes a `head` change still refreshes everything it should.
- **Rebase/merge churn** writing many files fast: classified as `mergeState`
  (+ `head` when commits land); the 400 ms debounce coalesces; graph re-logs only
  when a `head` event is in the window.

## Testing / verification

- **Pure unit:** `classifyGitChange` for each path family (HEAD, refs/x,
  packed-refs, FETCH_HEAD, MERGE_HEAD, rebase-merge/x, index, *.lock, junk);
  `scopesForChange` and `scopesForFocus(headMoved: true/false)` truth tables.
  Highest value, fastest.
- **Watcher:** `io_repo_watcher_test` emits the right `RepoChange` for touched
  files and still filters `index`/`*.lock`.
- **Auto-refresh widget/unit:** focus refresh invalidates `repoStatusProvider`
  but **not** `commitGraphDataProvider` (assert via a recording/override or a
  call-count fake); a `head` watcher event invalidates the graph; a `mergeState`
  event does not.
- **Gate:** `flutter analyze` + `flutter test` green (PR CI). Manual smoke on
  Windows: open a large repo, alt-tab away/back repeatedly → no graph reload /
  no lag; run a fetch → branches/graph update; edit a file in an external editor
  while unfocused → on focus the change list updates.

## Risks / notes

- **Mis-classification → staleness.** Mitigated by conservative maps (`head`
  refreshes everything; when unsure the union widens) and the focus headSha
  safety net. The pure classify/scope functions are unit-tested exhaustively.
- **`headSha` safety net depends on status carrying it** — confirmed
  (`RepoStatus.headSha`). If status fails to load, focus still refreshes
  `worktree`/`state`; refs simply won't refresh that cycle (next `.git` event
  will).
- **Moving the graph provider** is a mechanical extraction; the panel keeps its
  `skipLoadingOnReload` behavior. No functional change to the graph itself.
- Independent of the flicker fix (`fix/sidebar-refresh-flicker`): that keeps
  data visible during reloads; this reduces how often reloads happen. They
  compose cleanly and touch mostly different code.
