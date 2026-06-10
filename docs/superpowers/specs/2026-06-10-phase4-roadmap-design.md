# Phase 4 Roadmap — Post-Program Audit

**Date:** 2026-06-10
**Status:** approved (execute slice by slice, 1–2 PRs each)
**Owner:** zN3utr4l

## Context

The 2026-06 debt-first improvement program is complete (PRs #13–#25,
v0.1.12): facade layering, infra/UI god-file splits, application purity,
typed read errors, Phase 2 UX and Phase 3 features. A post-program audit
(deep read + daily use) surfaced 16 concrete gaps, verified against the
code:

- `branch_tree_view.dart` context-menu checkout passes the node name
  verbatim to `git checkout` — for remote nodes (`origin/x`) this detaches
  HEAD instead of creating a tracking local branch.
- `commit_graph_panel.dart` `tag_here` prompts only for a name; the
  `message` parameter exists end-to-end in the backend but is never sent,
  so UI tags are always lightweight.
- `safeCheckout` (dirty-tree stash/discard offer) is only wired to
  double-click; context-menu checkout surfaces the error without recovery.
- Sidebar `push_tag` and per-remote fetch still bypass the facade (no
  auth-retry, no progress).
- `sidebarDataProvider` loads branches→tags→remotes→stashes→submodules→
  worktrees with six sequential awaits.
- No auto-refresh: status/graph update only on F5 or after actions.
- Diffs are buffered whole; giant diffs (lock files, generated) need a cap.
- The push button is plain `git push` although the backend supports
  `--force-with-lease`, explicit branch/remote and `--tags`.
- Diff is unified-only (no side-by-side, no ignore-whitespace); conflicts
  have no per-file take-ours/theirs; staging is hunk-level only; stash has
  no preview/partial; a11y covers the sidebar only; no one-click undo
  commit; no GPG badge; graph/sidebar widgets have no widget tests; two
  real-git fixture tests flake under full-suite load with the failure
  output never captured.

`main` is protected → every slice ships as PR(s) with CI green and a
version bump when `lib/` changes (CD auto-releases `v<version>`). New git
operations get dedicated TDD (real-git fixture tests at the infra layer,
unit tests at application/controller layers).

## Decisions

- **Scope:** full program — all 16 audit items.
- **Auto-refresh approach:** file-watcher on `.git/` only (HEAD, refs/,
  packed-refs, index, MERGE_HEAD, rebase state dirs) with debounce, plus a
  status refresh when the window regains focus. No working-tree watcher
  (cost/risk on large repos); focus-refresh covers external edits on
  return. Settings toggle to disable.
- **Slicing:** by theme, value-first (fixes → perf → push/diff UX →
  conflicts/staging → stash/undo/a11y → widget tests). Flaky-test
  instrumentation lands in S1 so every suite run during the program is a
  capture attempt.

## Slices (execution order S1 → S6)

### S1 — Real fixes (S–M, high value, low risk)

1. **Checkout remote branch → tracking local branch.** Remote branch nodes
   (context menu *and* double-click) get "Checkout as local branch": strip
   the remote prefix; if a local branch with that name exists, checkout
   that (via `safeCheckout`); otherwise `git checkout -b <name> --track
   <remote>/<name>`. New `--track` capability in the ref writer + facade
   method (`checkoutRemoteBranch`).
2. **Annotated tags from the UI.** The `tag_here` prompt gains an optional
   multiline *Message* field; non-empty → annotated tag. Backend `message`
   param already plumbed (`createTag` in controller/service/writer).
3. **safeCheckout at every entry point.** All checkout paths (branch
   context menu, ref pills, graph rows, branch dropdown) route through
   `safeCheckout` so a dirty working tree offers stash/discard exactly
   like double-click does.
4. **Sidebar `push_tag` + per-remote fetch through the facade.** New
   `pushTag(repo, tag, remote)` and `fetchRemote(repo, remote)` on
   `GitActionsService`/`GitActionsController` with prompt (auth-retry) and
   progress wiring; sidebar callsites switched over.
5. **Flaky-test instrumentation (audit #16).** A failure-capture helper
   around the two flaky real-git tests (`getCommits` skip/take,
   `getFileHistory` author): on failure, dump the git command output,
   stderr and fixture repo state to the test log. No behavioural change to
   the tests themselves — capture first, fix later.

### S2 — Performance (M; auto-refresh is the risky piece)

6. **Parallel sidebar load.** `Future.wait` over the six independent loads
   in `sidebarDataProvider` (branches via the shared provider included).
7. **Auto-refresh.** New `RepoWatcher` port in application (start/stop per
   repo, debounced change events) + infrastructure impl using
   `Directory.watch` on `.git/` with ~400 ms debounce. Events invalidate
   status/graph/sidebar providers; window-focus listener refreshes status.
   Debounce absorbs our own operations' churn (no self-trigger
   suppression needed initially). Settings toggle (default on). Unit
   tests with a fake event source; one real-git integration test.
8. **Diff cap.** The read facade caps per-file diff output (default
   threshold 2 000 lines, an application-layer constant) and marks the
   result `truncated`; the diff panel shows "Load full diff" which
   re-fetches that file uncapped.

### S3 — Advanced push + diff UX (M)

9. **Push split-button.** Default action = current push; dropdown:
   *Force push (--force-with-lease)* behind a confirm dialog, *Push tags*,
   *Push branch…* (branch/remote picker). Backend support already exists.
10. **Diff modes.** Side-by-side toggle (unified ↔ split), reusing
    `pairChangedLines`/`HunkLines` from the intraline work; ignore-
    whitespace toggle re-running the diff with `-w` (new read-op param).

### S4 — Conflicts + fine-grained staging (M–L; line staging is hairiest)

11. **Take ours/theirs per file** in the conflict panel
    (`git checkout --ours|--theirs <file>` + `git add <file>`, via facade).
12. **Line-level staging.** Pure `buildPatchForLines` next to
    `buildPatchForHunks` (application, TDD-first); diff UI line selection →
    stage/unstage selected lines; discard-per-hunk via reverse patch
    behind a confirm dialog.

### S5 — Stash, undo, a11y (M)

13. **Stash preview + partial stash.** Stash content shown in the existing
    diff viewer (`stash show -p` equivalent via the read facade); partial
    stash from selected working-copy files (`stash push -- <paths>`,
    optional message).
14. **Undo last commit.** One-click soft reset (`reset --soft HEAD~1`)
    with confirm; enabled only when HEAD has a parent and no
    merge/rebase/cherry-pick is in progress.
15. **GPG signature badge** in commit details (`%G?` via the log reader).
16. **A11y pass 2.** Semantics on graph rows and working-copy rows,
    mirroring the #21 sidebar pass.

### S6 — Widget tests (M, no behaviour change)

17. **Widget tests for graph/sidebar/working-copy.** Fake providers;
    interaction tests (context-menu entries per node type, double-click →
    checkout, visibility toggles, row semantics). No goldens.

## Error handling

All new write operations go through the facade and inherit auth-retry,
progress, snackbar/error surfacing and provider invalidation. The watcher
must swallow and log filesystem errors (deleted repo, permission) and
auto-stop watching a repo that disappears. Truncated diffs must be
visually explicit (never silently partial).

## Testing

- Infra: real-git fixture tests for `--track` checkout, ours/theirs,
  partial stash, soft reset, `%G?`, `-w` diff.
- Application: pure-function TDD for `buildPatchForLines`, watcher
  debounce logic, diff cap/truncation.
- UI: controller unit tests for new facade methods; S6 adds the widget
  layer.
- Flaky pair: instrumented in S1, fixed only after a captured failure.
