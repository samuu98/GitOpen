# Faster network-op feedback + auth-resolution cache — design

**Date:** 2026-06-19
**Status:** Approved (design)
**Branch:** rides along on `feat/diff-horizontal-scroll` (user's choice).

## Problem

On a fetch (and every other network op) the user sees the blocking overlay flash
a generic **"Working…"** first, then change to **"Fetching origin"** with a
Cancel button — it reads as two popups. It also *feels* slow.

Root cause (verified in code):

1. `GitActionsController._run` (`git_actions_controller.dart:539`) calls
   `busy.begin()` with **no label**, so `BlockingOverlay` immediately shows its
   fallback label `'Working…'` (`blocking_overlay.dart:24`).
2. `GitActionsService._runStream` (`git_actions_service.dart:601`) then
   `await`s `_resolveProfile(repo)` **before** registering the operation
   (`progress.start(..., 'Fetching origin', ...)` at line 609). Only after that
   does the overlay switch to "Fetching origin" + Cancel.
3. `AuthResolver.resolveForRepo` (`auth_resolver.dart:48`) is the slow part: it
   spawns **up to two git subprocesses** before the op even starts —
   `remoteUrl` (host) at line 98 and `effectiveEmail` at line 76. On Windows
   process spawn is ~50–150ms each, so every network op pays ~100–300ms of
   auth-resolution latency, which is exactly the "Working…" window.

## Goal

- No "Working…" flash: the overlay shows the real label ("Fetching origin", …)
  from the first frame.
- Network ops feel faster: cut the per-op auth-resolution subprocess cost.

## Approach

Three changes, each independently testable.

### 1. Register the operation before resolving auth (cosmetic, removes the flash)

In `_runStream`, move `progress.start(...)` to **before** the
`await _resolveProfile(repo)`. The op's `kind`/`label`/`repo`/`onCancel` do not
depend on the resolved profile. Because `_runStream` runs synchronously up to
its first `await`, the operation registers before any frame is painted → the
overlay shows "Fetching origin" immediately, no "Working…".

Edge case: the user cancels during auth resolution. The `onCancel` sets
`cancelled = true` and completes `done`; after the `await` returns, guard with
`if (cancelled) { progress.failure(id, 'Cancelled'); return failed; }` so we do
**not** start the git stream (avoids a leaked subprocess).

### 2. Cache the slow git facts in `AuthResolver` (real speed)

**Deliberately cache the stable git *facts* (remote URL + effective email), not
the resolved profile.** The credential *selection* (binding lookup, store
lookup, email match) stays live on every call, so account switches / login /
logout remain correct with no cache invalidation. Only the two slow git reads
are memoised:

- `_remoteUrlCache` keyed by `'<repoId>|<remote>'`
- `_emailCache` keyed by `<repoId>`

Both use `containsKey` so a cached `null` is honoured. A public
`clearCache([String? repoId])` drops one repo's entries (or all).

### 3. Skip the email spawn when it can't matter (free win)

Email disambiguation only changes the result when a host has **more than one**
candidate profile. Today `effectiveEmail` is spawned unconditionally. Guard it:
only read the email when `candidates.length > 1`. For the common single-account
case this removes one of the two git spawns with zero behavioural change (all
existing resolver tests keep their results).

## Invalidation

The cached values are git facts independent of account selection, so:

- Account switch / login / logout → **no** invalidation needed (selection logic
  is live).
- Remote URL change (`addRemote` / `renameRemote` / `removeRemote` in
  `remotes_section.dart`) → call `clearCache(repoId)` after the write.
- Repo git-identity (email) change → rare; not auto-invalidated. If a stale
  email mis-selects an account, the existing auth-failure → account-prompt retry
  path recovers. Documented as an accepted edge.

## Components / boundaries

- `GitActionsService._runStream` (`git_actions_service.dart`): reorder + cancel
  guard. No signature change.
- `AuthResolver` (`auth_resolver.dart`): add the two caches, `clearCache`, the
  `candidates.length > 1` guard, and route `remoteUrl`/`effectiveEmail` through
  the caches. No signature change to `resolveForRepo`.
- `remotes_section.dart`: after add/rename/remove, call
  `ref.read(authResolverProvider).clearCache(repo.id.value)`.

## Testing

- **Service (reorder):** with a `resolveProfile` held pending by a `Completer`,
  assert `progress.start` has already fired while resolution is still pending.
  Existing success/auth-retry/cancel tests must still pass.
- **Resolver (skip email):** a counting `RepoIdentityReader` is **not** called
  when the host has ≤1 candidate, and **is** called (and decides) when >1.
- **Resolver (cache):** counting `RemoteUrlReader`/`RepoIdentityReader` are
  called once across two `resolveForRepo` calls; `clearCache()` forces a
  re-read.
- All existing `auth_resolver_test.dart` and `git_actions_service_test.dart`
  cases stay green.
