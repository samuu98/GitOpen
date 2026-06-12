# Auto-refresh on external repository changes — design

**Date:** 2026-06-12
**Status:** Approved

## Problem

GitOpen only refreshes a repository's state when the user acts (F5, fetch, or
an in-app write op). Commits, branch changes, or staging done by *other*
clients (git CLI, another GUI) are invisible until a manual refresh. The app
should stay current automatically.

## Decision

Watch each open repository's root directory with the `watcher` package
(cross-platform recursive watching; `dart:io`'s `Directory.watch` is not
recursive on Linux). Filter events to the ones that imply git state changed,
debounce, then bump that repo's existing revision counter
(`refreshRepo`/`repoRevisionProvider`), which already drives every repo-scoped
read provider. No provider rewiring.

Rejected alternatives:

- **Polling git state** every N seconds — perceptible latency and continuous
  git subprocesses multiplied by open tabs.
- **Refresh on window focus** — misses changes while the app stays visible;
  can be layered on later if ever needed.

## Components

### `lib/application/auto_refresh/repo_change_watcher.dart`

- `bool isRelevantRepoEvent(String repoRoot, String eventPath)` — pure
  classifier:
  - Paths under `.git/` are relevant only for: `HEAD`, `ORIG_HEAD`,
    `MERGE_HEAD`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`, `packed-refs`,
    and anything under `refs/`. `*.lock` files are never relevant.
    Everything else under `.git` (objects, logs, FETCH_HEAD, gc churn) is
    noise.
  - `index` is deliberately NOT relevant (changed 2026-06-12 after a field
    incident): the app's own `git status` runs rewrite `.git/index` to
    refresh the stat cache, so each refresh scheduled the next one — a
    self-sustaining loop that reloaded the graph every ~3 s and froze the
    UI. External staging is still picked up indirectly (worktree edits, and
    the eventual commit moves HEAD/refs).
  - Paths outside `.git` (working tree) are relevant — they refresh the
    working-copy panel.
- `RepoChangeWatcher` — owns one watcher stream for a repo root.
  - Constructor takes the repo root, an `onChanged` callback, an injectable
    watch-stream factory (`Stream<WatchEvent> Function(String path)`, default
    wraps `DirectoryWatcher`) and an injectable debounce duration
    (default 600 ms) so tests use synthetic streams and `fake_async`.
  - Trailing debounce coalesces event bursts (an external fetch touches many
    refs → exactly one refresh).
  - Stream errors (network drive, deleted directory): log a warning and stop
    that watcher; never crash. A stopped watcher is recreated by the next
    reconcile (e.g. tab switch or settings toggle).
  - `dispose()` cancels the subscription and any pending debounce timer.

### Shell wiring (`lib/main.dart`)

Same idempotent reconcile pattern as `_reconcileAutoFetchTimer`: keep a
`Map<RepoLocation, RepoChangeWatcher>`, reconciled on every build against the
open workspaces and the `autoRefreshEnabled` setting. Open tab without watcher
→ create; closed tab → dispose; setting off → dispose all. `onChanged` calls
`refreshRepo(ref, repo)`. A watcher killed by a stream error stays in the map
as a tombstone — recreating it on every build would respawn it endlessly while
the error persists; it is recreated when the tab is reopened or the setting
toggles.

Redundant triggers from the app's own write operations (they also touch
`.git`) are accepted: the debounce coalesces them and reads are idempotent.

### Settings

`autoRefreshEnabled` on `AppSettingsState`, **default true**, persisted like
the other flags, with a toggle in Settings → General mirroring the
auto-fetch row ("Auto-refresh when the repository changes on disk").

## Testing

- Filter: `.git` relevant/irrelevant paths, lock files, refs, worktree paths,
  Windows and POSIX separators.
- `RepoChangeWatcher`: synthetic stream + `fake_async` — burst of events →
  single callback after debounce; irrelevant-only events → no callback;
  stream error → no crash, watcher stops; dispose cancels pending timer.
- Settings round-trip for the new flag.
- No real filesystem in tests.

## Future (out of scope)

- Two-tier refresh (worktree events refresh only status providers, `.git`
  events refresh everything) if full refreshes ever prove too heavy on busy
  worktrees (e.g. builds running inside the repo).
