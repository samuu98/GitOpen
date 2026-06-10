# GitOpen — Completeness & Professional Polish Pass (2026-06-10)

## Goal

Close the gap between the (nearly complete) git backend and the UI, make every
daily action reachable and convenient, and formalize the visual design system so
the app reads as a professional product (Fork-grade), not an alpha.

Baseline: branch `fix/audit-phase1-2`, `flutter analyze` clean, 116+ tests green.
Source inventory: 3-agent exploration on 2026-06-10 (actions coverage, UI audit,
stub scan — no stubs found; backend ops exist for almost everything).

## Scope decisions

**In scope (this pass):**

1. **Design system formalization** — the single highest-ROI professionalism fix.
   - `lib/ui/theme/app_typography.dart`: semantic text scale (headingL/M,
     body, bodySmall, label, mono, monoSmall) exposed as a `ThemeExtension`
     so widgets read it via context like `AppPalette`.
   - `lib/ui/theme/app_metrics.dart`: spacing scale (xs..xxl), shared paddings,
     radii, icon sizes, animation durations.
   - Wire both into `ThemeData` in `main.dart`; respect the user's custom
     `fontFamily` setting (currently only partially applied).
   - Apply to high-visibility surfaces: context menus, dialogs, sidebar section
     headers, status bar, commit row, toolbar. Replace `Opacity(0.4)` disabled
     hack with proper disabled colors.

2. **Action completeness (backend exists, UI missing):**
   - **Push** becomes a split-button/dropdown: Push (default), Push
     `--force-with-lease` (confirm dialog), Push tags.
   - **Fetch** dropdown: Fetch, Fetch + prune (new `prune` flag on backend
     `fetch`), Fetch all remotes.
   - **Pull** dropdown: default strategy + one-shot override (ff-only / merge /
     rebase).
   - **Merge preview**: `previewMerge` (already implemented, never called) wired
     into `MergeDialog` — shows "clean merge" or list of conflicting files
     before the user commits to the merge.
   - **Stash list modal → interactive**: per-stash Apply / Pop / Drop / View
     diff (new read op `getStashDiff` via `git stash show -p --include-untracked`).
   - **Commit context menu**: Copy message (new read use of existing
     `getCommitFullMessage`), Open on remote (web URL derived from origin URL,
     supports GitHub/GitLab/Bitbucket https+ssh forms).
   - **Command palette**: register the new actions (push force, pull rebase,
     stash, open on remote).

3. **New features (small but high-value):**
   - **File history**: context-menu action on working-copy files and committed
     file tree entries → dialog listing commits touching the path
     (`git log --follow`), each expandable to its diff for that file.
   - **Restore file at commit**: from file history / file tree, `git restore
     --source <sha> -- <path>` (new write op `restoreFileAt`) with confirmation.

4. **Targeted polish:**
   - Status bar: vertical separators, 12px text, primary running operation with
     progress instead of bare count, warning style when no auth account.
   - Context menus: proper left padding, right-aligned shortcut hints.
   - Welcome screen: app-styled buttons (no raw Material defaults).
   - Tooltips with shortcuts on all icon-only buttons.

**Out of scope (documented backlog, separate PRs):**
- Interactive rebase UI (reorder/squash/reword) — needs a sequence-editor
  bridge + dedicated modal; biggest remaining gap but too risky to bundle here.
- Blame view, submodule/worktree management, GPG signing, bisect, archive.
- Multi-window drag-out; hosting integrations (PRs/MRs).

## Architecture notes

- New read/write ops follow the existing pattern: interface in
  `lib/application/git/git_{read,write}_operations.dart`, impl in
  `lib/infrastructure/git/git_cli_*`, real-repo tests in
  `test/infrastructure/git/` via `RepoFixture`.
- Web-URL derivation lives in `lib/application/git/remote_web_url.dart` (pure
  function, unit-testable: ssh and https remotes → browse/commit/branch URLs).
- Typography/metrics are `ThemeExtension`s — no behavioural coupling; widgets
  migrate incrementally (full sweep of high-visibility surfaces now, long tail
  opportunistically).
- All new UI actions run through the existing `OperationsNotifier`/toast path
  and per-repo invalidation (`refreshRepo`).

## Testing

- Unit tests for: remote web URL derivation, fetch --prune flag, stash diff,
  restoreFileAt, file history read op.
- Existing suite must stay green; `flutter analyze` must stay clean.
- Manual smoke-test checklist appended to the PR description (push variants,
  merge preview, stash modal, file history).

## Delivery

One commit per phase on `fix/audit-phase1-2`:
1. `feat(theme): typography + metrics design system`
2. `feat(git): expose push/fetch/pull variants, merge preview, stash manager`
3. `feat(files): file history + restore at commit`
4. `feat(ui): status bar, menus, welcome polish`
