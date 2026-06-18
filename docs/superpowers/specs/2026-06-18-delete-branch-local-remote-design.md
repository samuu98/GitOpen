# Delete a branch locally and on the remote together

**Date:** 2026-06-18
**Status:** Approved design, pending implementation plan

## Problem

Deleting a branch is a two-step chore: remove the local branch, then remove its
remote counterpart (or vice-versa). In GitOpen today the sidebar branch context
menu has a single **Delete** that only runs `git branch -d` — it never deletes
the remote, and on a remote-branch row it does the wrong thing (it does not pass
`remote: true`, so `git branch -d origin/feature` just fails). There is no way to
remove both sides in one action.

## Goal

One **Delete** action (sidebar branch context menu) that can remove the local
branch and its tracked remote branch together, via a confirmation dialog that
lists whichever sides exist and lets the user choose. Deleting the remote side
is a `push --delete`, so it must use the same resolved credential as push/fetch
(the multi-account resolution added in 1.2.0).

## Decisions (locked during brainstorming)

- **One "Delete" with a choice dialog.** Checkboxes for "Local branch X" and
  "Remote branch Y", both checked by default when present. If a side does not
  exist, its row is omitted.
- **On the current branch:** the local checkbox is disabled (git refuses to
  delete the checked-out branch); the remote can still be deleted.
- **Unmerged local branch:** delete with `-d` (safe); if git refuses because the
  branch is not fully merged, surface the error and offer a **Force** action
  that retries with `-D`.
- **Independent sides:** attempt each selected side and report failures per
  side; a remote failure does not cancel the local delete (and vice-versa).
- **Remote delete is auth-aware:** routed through the push-style auth-retry path.

## Design

### 1. Pairing — `branchDeletionTargets` (pure)

New pure function (application layer), unit-testable, that maps the
right-clicked [Branch] plus the full branch list to the deletion targets.

```dart
// lib/application/git/branch_deletion.dart
class BranchDeletionTargets {
  const BranchDeletionTargets({
    this.localName,
    this.localIsCurrent = false,
    this.remoteRef,
  });
  final String? localName;     // e.g. "feature"  (null if no local side)
  final bool localIsCurrent;   // true => local cannot be deleted (checked out)
  final String? remoteRef;     // e.g. "origin/feature" (null if no remote side)
}

BranchDeletionTargets branchDeletionTargets(Branch clicked, List<Branch> all);
```

Rules (formats confirmed in `git_cli_ref_reader`):
- Local ref: `name="feature"`, `fullName="refs/heads/feature"`,
  `upstreamFullName="refs/remotes/origin/feature"` (or null).
- Remote ref: `name="origin/feature"`, `fullName="refs/remotes/origin/feature"`.

- **Clicked is local** (`!isRemote`): `localName = clicked.name`,
  `localIsCurrent = clicked.isCurrent`. `remoteRef` = `clicked.upstreamFullName`
  with the `refs/remotes/` prefix stripped (→ `origin/feature`), or null when
  `upstreamFullName` is null or not under `refs/remotes/`.
- **Clicked is remote** (`isRemote`): `remoteRef = clicked.name`
  (already `origin/feature`). `localName` = the `name` of the local branch
  (`!isRemote`) whose `upstreamFullName == clicked.fullName`; `localIsCurrent` =
  that local branch's `isCurrent`. Both null/false when no local tracks it.

### 2. Remote delete made auth-aware

`git_cli_ref_writer.deleteBranch(remote: true)` currently runs
`push <remote> --delete <branch>` through the non-streaming, credential-less
`GitResultRunner`. A `push --delete` needs credentials.

Add a streaming, auth-injecting method to the sync writer (mirrors `push`):

```dart
// lib/infrastructure/git/git_cli_sync_writer.dart
Stream<GitProgress> deleteRemoteBranch(
  RepoLocation r,
  String remoteRef, {           // "origin/feature"
  AuthSpec? auth,
}) async* {
  // split remoteRef into <remote> + <branch>, then:
  //   git -c credential.helper=… push --progress <remote> --delete <branch>
}
```

Expose it on `GitWriteOperations` and call it from a new
`GitActionsService.deleteRemoteBranch(...)` that drives it through the existing
`_runStream` auth-retry loop (same as `push`/`fetch`, reusing the resolved
profile). The old `GitCliRefWriter.deleteBranch(remote: true)` branch is removed
(remote deletion now goes only through the auth-aware path); the local path
(`branch -d/-D`) stays in the ref writer.

### 3. Local delete (with force on demand)

Reuse the existing local delete: `GitActionsService.deleteBranch(repo, name,
force: false)` → `git branch -d`. On failure, the result already carries git's
stderr; the orchestrator classifies "not fully merged" so the UI can offer a
**Force** retry that calls the same with `force: true` (`git branch -D`).

A small helper detects the not-merged case from stderr (git says
`not fully merged`):

```dart
bool isNotFullyMergedError(String stderr); // matches "not fully merged"
```

### 4. Orchestration — `GitActionsService.deleteBranchTargets`

```dart
Future<BranchDeleteOutcome> deleteBranchTargets(
  RepoLocation repo, {
  String? remoteRef,            // delete remote side when non-null
  String? localName,            // delete local side when non-null
  bool forceLocal = false,
  required AuthPrompt prompt,    // for the remote (auth-retry)
  required ProgressSink progress,
});
```

Behavior:
- If `remoteRef != null`: run the auth-aware remote delete (progress + retry).
- If `localName != null`: run local delete (`force: forceLocal`).
- Sides are independent: a failure on one does not skip the other.
- Returns `BranchDeleteOutcome { bool remoteOk?, bool localOk?, bool
  localNeedsForce, String? message }` so the UI can: show a per-side result, and
  if `localNeedsForce` (local failed, not-merged, force was off) offer Force.

### 5. UI — `DeleteBranchDialog` + wiring

`branch_tree_view`'s existing `case 'delete'` is replaced: instead of a plain
confirm, it computes `branchDeletionTargets(branch, allBranches)` and shows
`DeleteBranchDialog`:

- Renders only the present sides:
  - "Local branch `feature`" checkbox — checked by default; **disabled** with a
    hint when `localIsCurrent` ("current branch — checkout another first").
  - "Remote branch `origin/feature`" checkbox — checked by default.
- A dangerous **Delete** button returns the user's selection
  (`deleteLocal`, `deleteRemote`).
- On confirm, call `controller.deleteBranchTargets(...)`. If the result reports
  `localNeedsForce`, show a follow-up confirm ("Branch not fully merged. Force
  delete?") and retry with `forceLocal: true`.
- The remote delete surfaces progress via the operations/toast system (same as
  push). After completion, refresh the sidebar (`sidebarDataProvider`).

`allBranches` comes from `branchesProvider(repo)` (already used by
`compare_with`).

### 6. Error handling & edge cases

- Remote delete fails (auth/network): reported via progress/toast with git's
  stderr; local delete still attempted if selected.
- Local not-merged: Force offered (§3/§4).
- Local is current: checkbox disabled; only remote deletable.
- Clicked local has no upstream, or clicked remote has no tracking local: only
  the one available side is shown.
- No sides selected → no-op (Delete button disabled when nothing checked).

## Testing

- `test/application/git/branch_deletion_test.dart` — pure `branchDeletionTargets`:
  local with/without upstream; remote with/without a tracking local; current
  local; upstream not under refs/remotes (defensive → null); plus
  `isNotFullyMergedError` true/false.
- `test/application/git/git_actions_service_*_test.dart` — `deleteBranchTargets`
  with fakes: remote-only, local-only, both; remote fails but local proceeds;
  local not-merged → `localNeedsForce`; force path succeeds.
- `test/infrastructure/git/git_cli_write_operations_*_test.dart` —
  `deleteRemoteBranch` builds `push <remote> --delete <branch>` and injects the
  credential header (mirror existing sync-writer/auth tests).
- `test/ui/...` — light `DeleteBranchDialog` widget test: both rows present and
  checked; local row disabled when current; returns the chosen selection.

## Non-goals

- Multi-branch (bulk) deletion.
- Automatic pruning of stale remote-tracking refs.
- The toolbar branch dropdown's delete (stays local-only, out of scope).
