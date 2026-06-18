# Branch sync UX: divergence badges, fetch prune, blocking operation overlay

**Date:** 2026-06-18
**Status:** Approved design, pending implementation plan

## Problem

Three gaps when working with remotes:

1. **No divergence at a glance.** The sidebar shows local branches with no
   ahead/behind information; only the status bar shows it for the current
   branch. You can't see which branches need a pull or a push.
2. **Fetch leaves stale remote branches.** `git fetch` runs without `--prune`,
   so branches deleted on the server (e.g. after a PR merge) linger in the
   sidebar forever.
3. **No guard during operations.** While a fetch/checkout/merge is running the
   UI stays fully interactive, so you can start another action or navigate and
   leave the repo in a bad state.

## Goal

- Show an ahead/behind badge (`↑ahead ↓behind`) next to each diverged local
  branch in the sidebar, and next to the active **repo name** (current branch)
  in the title bar.
- Make `git fetch` prune deleted remote-tracking branches.
- Block all interaction behind a modal overlay while any git operation runs,
  with a Cancel button for cancelable (network) operations.

All three ship as one feature.

## Decisions (locked during brainstorming)

- Badge on **both** sidebar branches and the repo name.
- Per-branch ahead/behind is computed by a **separate async provider** so the
  fast initial branch load is not slowed.
- `fetch` **always** prunes (`--prune`).
- The blocking overlay covers **every** controller action (network + local).
- **Cancel** is offered only for network operations (fetch/pull/push/clone),
  by killing the git process; local operations block without Cancel.

## Design

### Part C — Prune on fetch

`GitCliSyncWriter.fetch` builds `['fetch', '--progress', …]`. Add `--prune`:
- `git fetch --prune --progress` (single remote / default),
- `git fetch --prune --progress --all` (all remotes).

This removes remote-tracking refs deleted upstream. No new setting — always on.

### Part A — Divergence data + badges

**Pure parser.** Extract/reuse the existing `aheadBehindRe` into a pure
`parseAheadBehind(String track) -> ({int ahead, int behind})` in the ref-reader
area, so both the remote-branch reader and the new divergence reader share it.
Handles `[ahead 2, behind 3]`, `[ahead 2]`, `[behind 1]`, `[gone]` (→ 0/0),
and `''` (in sync → 0/0).

**Divergence reader + provider.**
- Add `GitCliRefReader.localBranchDivergence(repo) -> Map<String, ({int ahead,
  int behind})>` running `for-each-ref refs/heads
  --format='%(refname)%00%(upstream:track)'`, parsed via `parseAheadBehind`,
  keyed by branch short name. Bounded by the same streaming/timeout guard the
  reader already uses for refs.
- Expose `branchDivergenceProvider(RepoLocation)` (FutureProvider.family),
  loaded in parallel — the sidebar renders branches immediately and the badges
  fill in when this resolves. It is invalidated by the same refresh signal as
  the rest of the sidebar (`sidebarDataProvider` / read-ops invalidation), so a
  fetch/commit updates it.

**Sidebar badge.** In `branch_tree_view`, for a local branch row, look up its
short name in the divergence map; when `ahead > 0 || behind > 0`, render a small
badge `↑$ahead ↓$behind` (omit a zero side: `↑2`, `↓3`, or `↑2 ↓3`). No badge
when in sync or when the branch has no upstream (absent from the map / 0/0).

**Repo-name badge.** `RepoSelector` (title bar) shows the active repo name.
Add the current branch's ahead/behind from `repoStatusProvider(repo)` (the same
source the status bar uses) as a `↑a ↓b` badge after the name; hidden when 0/0.

### Part B — Blocking operation overlay

**Busy state.** A `BusyNotifier` (StateNotifier) holding
`({int depth, String? label, void Function()? onCancel})`:
- `begin(String label, {void Function()? onCancel})` → depth++ and records the
  label/onCancel (the most recent op).
- `end()` → depth--; clears label/onCancel when depth hits 0.
- Exposed as `busyProvider`.

**Wire every action.** In `GitActionsController`, both `_run` and `_runLocal`
wrap their work:
```
busy.begin(label, onCancel: canceler);
try { ... } finally { busy.end(); }
```
- For `_runLocal` (local ops) `onCancel` is null → no Cancel button.
- For `_run` (streaming ops) `onCancel` kills the git process (see below).
- The label comes from the op (e.g. "Fetching", "Checking out feature").

**Overlay.** `BlockingOverlay` added to the Shell `Stack` (above `ToastOverlay`):
when `busy.depth > 0`, render a full-screen `ModalBarrier` (absorbs all input)
+ a centered card with a spinner, the current `label`, and a **Cancel** button
shown only when `onCancel != null`. Nothing behind it is interactive.

**Cancel for network ops.** Streaming ops need a real canceller:
- `GitCliSyncWriter._runProgressStream` holds the spawned `Process` and, when
  its stream subscription is cancelled, kills it (`proc.kill`). The op surfaces
  a `void Function()` canceller up through `GitActionsService._runStream`
  (which already drives the stream) to the controller, which passes it as
  `busy.begin(onCancel:)`. Cancelling kills the process; the stream ends, the
  op finishes as failed/cancelled and `end()` runs via the `finally`.
- Local ops are not cancelable (killing mid-`checkout`/`merge` risks a dirty
  state); their overlay has no Cancel.

### Components / files (high level)

- `lib/infrastructure/git/git_cli_sync_writer.dart` — `--prune`; process-kill
  cancel in `_runProgressStream`.
- `lib/infrastructure/git/git_cli_ref_reader.dart` — pure `parseAheadBehind`;
  `localBranchDivergence`.
- `lib/application/git/...` / `providers.dart` — `branchDivergenceProvider`;
  thread the canceller through the read/service layer where needed.
- `lib/application/operations/busy_notifier.dart` (new) + `busyProvider`.
- `lib/ui/git/git_actions_controller.dart` — busy begin/end around actions.
- `lib/ui/sidebar/branch_tree_view.dart` — sidebar badge.
- `lib/ui/shell/repo_selector.dart` — repo-name badge.
- `lib/ui/operations/blocking_overlay.dart` (new) + wired into `main.dart` Shell.
- `lib/ui/sidebar/divergence_badge.dart` (new) — shared `↑a ↓b` badge widget.

## Error handling & edge cases

- Branch with no upstream / in sync → no badge.
- `[gone]` upstream → treated as 0/0 (no badge); deletion handled by prune.
- Divergence provider slow/times out on a huge repo → badges simply don't show
  (the reader's existing timeout guard applies); the rest of the UI is fine.
- Nested operations → busy `depth` counter; overlay stays until all finish.
- Overlay must never deadlock: `end()` is in a `finally`, so an exception still
  clears busy.
- Cancel kills the process → the op completes as a failure (surfaced normally);
  no partial-write risk for network ops.

## Testing

- `parseAheadBehind` — pure: `[ahead 2, behind 3]`, `[ahead 2]`, `[behind 1]`,
  `[gone]`, `''` → expected pairs.
- `localBranchDivergence` — fixture repo with an ahead branch, a behind branch,
  an in-sync branch, and an upstream-less branch → expected map.
- `BusyNotifier` — begin/end nesting: depth, label, onCancel transitions;
  `end()` at depth 0 clears.
- `BlockingOverlay` widget test — hidden at depth 0; shown + absorbs taps at
  depth > 0; Cancel present only when `onCancel != null` and invokes it.
- `DivergenceBadge` widget test — renders `↑2 ↓3`, omits zero sides, empty for
  0/0.
- fetch args include `--prune` (extend the existing fetch write-op test).

## Non-goals

- Periodic auto-fetch.
- Pull/push triggered from the badges (display only).
- Cancel for local operations.
- A user setting to toggle prune.
