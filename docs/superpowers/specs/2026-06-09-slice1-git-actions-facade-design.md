# Slice 1 — Git-actions facade + layering

**Date:** 2026-06-09
**Status:** draft (awaiting review)
**Owner:** zN3utr4l
**Part of:** the refactoring roadmap (`2026-06-08-refactor-roadmap-design.md`), Slice 1 — "highest leverage".
**Depends on:** PR #13 (in-app merge editor) merged to `main`. The Slice 1 branch cuts from `main` once #13 lands.

## Problem (grounded in current code)

Every UI widget calls the git ops directly and re-implements the same
orchestration. Three concrete consequences:

1. **A real bug — F5 fetch has no auth-retry.** The toolbar's Fetch button runs
   through `_runStream` (`lib/ui/toolbar/git_toolbar.dart:120-225`), which on an
   auth / wrong-account failure opens `AccountSwitcherDialog`, binds the chosen
   profile, and retries once. The F5 shortcut instead calls `_fetchActive`
   (`lib/main.dart:180-206`), which **duplicates** the progress plumbing but
   `catch`es into `ops.finishFailure(id, e.toString())` with **no retry** — an
   auth failure dies silently in a toast.

2. **~15 duplicated call sites.** The pattern `start op → drive progress →
   handle GitResult → invalidate providers → surface snackbar/toast` is repeated
   (toolbar fetch/pull/push, F5, branch create/delete, graph cherry-pick/
   revert/reset, stash, conflict continue/abort, …). Only the toolbar's
   streaming ops carry auth-retry; everything else is a bare call with
   inconsistent (often absent) feedback.

3. **Layering leaks** (UI reaching into infrastructure / `dart:io` / `http`):

   | Leak | File:line | Target home |
   |------|-----------|-------------|
   | dead `import` of infra `GitProcessRunner` | `ui/toolbar/git_toolbar.dart:16` | delete |
   | `import` infra `app_logger` (+ `appLog.*`) | `ui/commit_graph/commit_graph_panel.dart:23`, `ui/sidebar/sidebar.dart:18` | `LoggerPort` (application) |
   | `Process.run` to open external editor | `ui/conflicts/conflict_resolution_panel.dart:164` | `ExternalEditorLauncher` (application port → infra) |
   | `Process.run` `git ls-remote` (test credential) | `ui/settings/sections/authentication_section.dart:205` | `CredentialTester` (application port → infra) |
   | `http.get api.github.com/user` | `ui/dialogs/auth_dialog.dart:273` | `GitHubUserService` (infra) |

   Plus helpers to consolidate: `_appPromptText` (`git_toolbar.dart:526`),
   `_revealCommit` (`sidebar.dart:31`), `currentBranchName` (duplicated across
   `merge_dialog.dart:278`, `sidebar.dart:931`, `commit_graph_panel.dart:515`),
   and the merge/rebase-outcome → conflict flow (duplicated across graph,
   sidebar, conflict panel).

## Goal / non-goals

**Goal.** One path for every git action: a pure application **`GitActionsService`**
owning sequencing + auth-retry + op lifecycle + declarative invalidation, driven
by ports; a thin UI **`GitActionsController`** that implements the ports and is
the single call site for all widgets *and* F5. Remove the five layering leaks.
Consolidate the four helpers.

**Behaviour is preserved**, with exactly one intended change: **F5 fetch gains
the same auth-retry as the toolbar** (the bug fix) — covered by a dedicated test.

**Non-goals (explicitly deferred):**
- Unifying the read/write error model (reads still `throw GitProcessException`)
  → **Slice 5**. Slice 1 keeps the current stderr-string auth classification,
  merely *relocating* it into the service.
- Full application-layer DI purity (`auth_resolver` `dart:io`, `OperationsNotifier`
  holding `Process?`) → **Slice 4**.
- Splitting the god-files (`git_toolbar`, `sidebar`, …) → **Slices 2-3**. Slice 1
  *removes* code from them (orchestration → service) but does not restructure
  what remains.

## Architecture

```
        UI widgets + F5 ─────────────┐
                                      ▼
                       GitActionsController  (lib/ui/git/, thin)
                         implements the ports below; single call point
                         ├─ AuthPrompt      → AccountSwitcherDialog / AuthDialog
                         ├─ ProgressSink    → operationsProvider (toast/activity)
                         └─ applies ActionResult: ref.invalidate(...) + snackbar
                                      │ calls
                                      ▼
                       GitActionsService    (lib/application/git/, PURE)
                         owns: op sequencing, auth-error classify, retry-once,
                               declarative "what changed"
                         depends on: GitReadOperations, GitWriteOperations,
                                     AuthPrompt, ProgressSink, LoggerPort
```

### `GitActionsService` (application, pure — no Flutter, no dart:io)

One method per action. Streaming actions take the ports; local actions need
only the write op + return an `ActionResult`.

```dart
final class GitActionsService {
  GitActionsService(this._read, this._write, {LoggerPort? log});

  // Streaming + auth-retry (fetch/pull/push/clone)
  Future<ActionResult> fetch(RepoLocation r, {
    required AuthResolver resolveProfile,   // current bound profile
    required AuthPrompt prompt,             // interactive re-auth
    required ProgressSink progress,
  });
  // pull/push/clone: same shape.

  // Local writes (branch/tag/cherry-pick/revert/reset/stash/merge/rebase/
  // conflict continue|abort). No auth; return outcome + invalidation hints.
  Future<ActionResult> cherryPick(RepoLocation r, CommitSha sha,
      {required ProgressSink progress});
  // … one per action.
}
```

`ActionResult` is the declarative hand-back the controller applies:

```dart
final class ActionResult {
  const ActionResult(this.outcome, this.invalidate, {this.message, this.severity});
  final ActionOutcome outcome;       // success | conflict | upToDate | failed
  final Set<RepoDataScope> invalidate; // {commits, status, refs, repoState, …}
  final String? message;             // user-facing (controller shows snackbar)
  final MessageSeverity? severity;   // info | success | error
}
```

The service contains the **auth-retry logic** internally (classify failure →
`prompt.forAccount(...)` → if a profile comes back, bind + retry **once** →
otherwise `failed`). This is the logic moved verbatim from `_runStream`
(`_isAuthError`/`_isWrongAccountError` become private methods of the service).

### Ports (application)

```dart
// Interactive re-auth. Returns the chosen profile or null (user cancelled).
abstract interface class AuthPrompt {
  Future<AuthProfile?> forAccount(RepoLocation repo, AuthFailureReason reason);
}

// Op lifecycle / progress. Implemented over OperationsNotifier.
abstract interface class ProgressSink {
  String start(OpKind kind, String label, {RepoLocation? repo});
  void progress(String id, double? fraction, String phase);
  void success(String id);
  void failure(String id, String message);
}

// Logging without importing infra into UI or coupling the service to a concrete logger.
abstract interface class LoggerPort { void i(String m); void w(String m); }
```

`AuthFailureReason ∈ {authRequired, wrongAccount}` (replaces the two bool
helpers). `OperationsNotifier` gets a tiny adapter implementing `ProgressSink`
(or implements it directly — it already exposes start/updateProgress/finish*).

### `GitActionsController` (UI, thin)

A `Provider`-exposed object holding `WidgetRef`; implements `AuthPrompt`
(showing `AccountSwitcherDialog`/`AuthDialog` and binding via
`appSettingsProvider.notifier.setAuthBinding`) and `ProgressSink` (delegating to
`operationsProvider`). Each public method calls the service then applies the
returned `ActionResult`: `ref.invalidate` the mapped providers and, if a
`message` is present, show it via a single `_snack(context, message, severity)`
helper (replacing the ~15 scattered `ScaffoldMessenger` blocks).

```dart
// Every widget AND main.dart's F5 intent funnel through this:
await ref.read(gitActionsControllerProvider).fetch(context, repo);
```

### Data flow — fetch with auth-retry (the unified path)

1. Controller.`fetch(context, repo)` → `service.fetch(repo, resolveProfile, prompt:this, progress:this)`.
2. Service: `progress.start(fetch,…)` → stream `write.fetch(auth)` → `progress.progress(...)`.
3. On auth/wrong-account failure: `prompt.forAccount(repo, reason)` →
   controller shows `AccountSwitcherDialog`. If a profile is returned, service
   binds + retries once; else returns `ActionResult(failed, …)`.
4. Success → `ActionResult(success, {commits, status, refs})`. Controller
   invalidates those + (no snackbar — the toast already conveys completion).
5. **F5** calls the *same* `Controller.fetch` → identical behaviour. Bug fixed
   by construction; `_fetchActive`'s bespoke copy is deleted.

### Leak extractions (own small commits within the slice)

- `ExternalEditorLauncher` (application port; infra impl wraps the existing
  `RepoLauncher`/process spawn) — consumed by conflict panel + settings; removes
  `dart:io` from `conflict_resolution_panel.dart`.
- `CredentialTester` (application port; infra impl does `git ls-remote`) —
  removes `dart:io` from `authentication_section.dart`.
- `GitHubUserService` (infra; sibling of `GitHubDeviceFlow`) — removes `http`
  from `auth_dialog.dart`.
- `LoggerPort` provider — removes the infra `app_logger` import from graph +
  sidebar.
- Delete the dead `GitProcessRunner` import in `git_toolbar.dart`.

### Helper consolidation

- `currentBranchName(read, repo)` → `lib/application/git/` (pure); call sites in
  merge_dialog/sidebar/graph point at it.
- `revealCommit(ref, sha)` → `lib/application/navigation/` (drives
  `selectedCommitShaProvider` + `scrollRequestProvider`).
- `promptText(context, …)` → `lib/ui/dialogs/` shared widget (stays UI — it *is*
  a dialog).

## Testing

The headline win: the service is **unit-testable without Flutter**. With fake
`AuthPrompt`/`ProgressSink` and the existing `RepoFixture` (or faked ops):
- fetch auth-retry: failure → prompt invoked → bind+retry → success; prompt
  returns null → `failed`, no retry.
- **F5 regression test:** the F5 action path invokes the auth-prompt on an auth
  failure (the bug fix — TDD: write it red against today's `_fetchActive`).
- each local action returns the right `ActionResult.invalidate` set.
- controller widget test (fake service): a returned `ActionResult` triggers the
  expected `ref.invalidate`s and snackbar (use the fake-port pattern from the
  merge-editor test — **no real git in widget tests**).
Acceptance: `flutter analyze` clean, full suite green, CI green, one PR.

## Build order (within the single Slice 1 PR)

1. Ports + `GitActionsService` + provider; unit tests (no call sites changed yet).
2. `GitActionsController` + provider; controller tests.
3. Migrate streaming ops (toolbar fetch/pull/push + **F5**) to the controller;
   delete `_runStream`/`_fetchActive` duplication. ← fixes the bug.
4. Migrate local actions (branch, graph context-menu, stash, conflict continue/
   abort) to the controller; centralise the snackbar helper.
5. Leak extractions (editor launcher, credential tester, GitHub user, logger
   port, dead import) + helper consolidation.
6. Verify: analyze, full suite, manual smoke per `docs/qa-checklist.md`.
