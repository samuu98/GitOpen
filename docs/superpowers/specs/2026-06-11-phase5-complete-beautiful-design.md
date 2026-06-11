# Phase 5 Roadmap — Complete & Beautiful (target v1.0.0)

**Date:** 2026-06-11
**Status:** approved (execute slice by slice, 1 PR each)
**Owner:** zN3utr4l

## Context

Phase 4 closed the post-program audit (PRs #26–#31, v0.1.17, 586 tests).
The product goal now changes from "fix gaps" to "make GitOpen a maximally
complete and aesthetically polished desktop git client", closing the
feature distance to Fork/GitKraken/Sublime Merge and shipping a showcase
v1.0.0. Owner decisions (2026-06-11):

- **Pillars:** full interactive rebase, diff/viewer extras, GitHub
  integration covering both pull requests *and* Actions workflow runs.
- **Aesthetics:** deep polish of the current design language — tokens,
  motion, consistency — not a redesign.
- **Goal line:** showcase v1.0.0 (rewritten README, branding; the CD
  already builds an Inno Setup installer and a .deb).
- Known leftovers (hunk-level unstage parity, a11y beyond current areas)
  stay out of scope except where a pillar naturally absorbs them
  (multiline messages land with interactive rebase; icon-button
  unification lands with the polish slice).

## Constraints

- Same architecture: clean application/domain/infrastructure/ui layers,
  system `git` CLI (no libgit2), drift + riverpod, dart:io only in
  infrastructure + composition root.
- `main` PR-gated; version bump per slice when `lib/` changes; CD
  releases `v<version>` on merge. v1.0.0 is bumped only in the final
  slice.
- TDD per convention: real-git fixture tests (infra), pure-function unit
  tests (application), controller/service unit tests, widget tests for
  new panels.
- No blanket `dart format` (pre-tall-style codebase): format only touched
  files.

## Slices (execution order S1 → S5)

### S1 — Full interactive rebase (L)

A dedicated interactive-rebase view: pick a base (branch/tag/commit),
list `base..HEAD` commits, drag to reorder, per-commit action
pick/reword/squash/fixup/drop, multiline message editor for
reword/squash. Validation before run (e.g. first entry cannot be
squash/fixup; at least one pick/reword survives).

- **Application:** `RebaseEntry` value object + pure
  `buildRebaseTodo(List<RebaseEntry>)` returning git-rebase todo-file
  content; pure validation helpers. TDD-first.
- **Infrastructure:** generalize the existing `_scriptedRebase` trick:
  `GIT_SEQUENCE_EDITOR` is a script that copies our generated todo file
  over git's; reword/squash messages are written to numbered files
  consumed by a `GIT_EDITOR` script with a counter (extends the single
  reword `cp` trick from #25). Conflict/stop outcomes map to the existing
  `RebaseOutcome` types; the conflict panel already handles paused
  rebases.
- **UI:** entry from graph context menu ("Interactive rebase from here")
  and branch context menu ("Interactive rebase onto…"); a full-content
  dialog (same pattern as the merge editor) with a
  `ReorderableListView`; action dropdown per row; message editor expands
  inline for reword/squash.

### S2 — Diff & viewer extras (M)

- **Image diff.** New read op `getFileBytes(repo, {sha|index|worktree},
  path)` (blob via `git show`/file read). The diff views detect image
  extensions (png/jpg/jpeg/gif/webp/bmp) and render an old/new
  side-by-side preview on a checkerboard background with byte-size and
  pixel-dimension labels. Cap: skip preview above 20 MB (explicit
  message). Binary non-image files keep the current "binary" notice.
- **File tree view.** Pure `buildFileTree(paths)` helper folding paths
  into a folder tree; a flat/tree toggle shared by the working-copy file
  list and the commit-details file list (persisted in settings).
- **Compare refs.** Branch context menu "Compare with current/Compare
  with…": a compare view showing ahead/behind commit lists (`git
  rev-list --left-right --count` + the two log ranges) and the combined
  diff (`getDiff` with a two-ref spec, which already exists).

### S3 — GitHub PRs + Actions (L)

- **Application:** `GitHubApi` port (`listPullRequests`,
  `listWorkflowRuns`, `prChecks`) + immutable models (`PullRequestInfo`,
  `WorkflowRunInfo`, `CheckSummary`). GitHub-ness detected from the
  `origin` remote URL (github.com only; others simply hide the panel).
  Typed `GitHubApiException` kinds: auth, rateLimit, network, notFound.
- **Infrastructure:** REST v3 implementation with an injectable
  `http.Client` (same testing pattern as device-flow polling). Token
  reused from the existing device-flow auth store; no `gh` CLI
  dependency.
- **UI:** a "GitHub" panel opened from the toolbar (exact docking chosen
  in the slice plan after inspecting the shell layout) with two tabs:
  *Pull Requests* — list (number, title, author, draft, check status)
  with per-PR checkout (fetch `pull/<n>/head` into a local branch via
  the facade) and open-in-browser; *Actions* — recent workflow runs for
  the current branch (status, conclusion, duration, open in browser).
  No token → inline CTA reusing the existing device-flow sign-in.
  Offline/rate-limited → inline non-blocking error with retry.

### S4 — Deep aesthetic polish (M–L)

Same design language, higher craft:

- **Tokens:** `AppSpacing` (4-px scale), `AppTypography`, `AppRadii`,
  `AppDurations` as theme extensions next to `AppPalette`; sweep
  hard-coded paddings/radii in the UI layer to tokens.
- **Motion:** implicit animations on hover/selection (rows, buttons,
  pills), animated panel/view transitions, ~120–200 ms curves.
- **Consistency:** one shared hover-icon-button widget replacing the ~10
  local variants (closes the old AppIconButton leftover); visible focus
  states everywhere; styled scrollbars; consistent tooltip delays.
- **Graph:** harmonized lane color palette (dark + light), redesigned
  ref pills (shape/contrast), subtle row hover.
- **Light theme:** contrast pass to AA on text/iconography.
- **Empty states:** icon + one-liner + action, consistent across panels.

No behaviour changes; existing widget tests must keep passing (semantics
labels preserved).

### S5 — Showcase v1.0.0 (S–M)

- README rewritten: hero screenshot + short GIF (captured after S4),
  feature matrix vs the old "Slice N" notes, install section pointing at
  the release installer/.deb, build-from-source section kept.
- CHANGELOG.md summarizing 0.1 → 1.0.
- Installer branding check (icon, app name, publisher).
- `pubspec.yaml` → `1.0.0+<n>`; merge → CD publishes v1.0.0.

## Error handling

New write operations go through the facade (auth-retry, progress,
snackbars, invalidation). Interactive rebase validates the todo before
running and surfaces stops through the existing conflict-panel flow.
GitHub API failures are typed and rendered inline (never block local git
work; the panel degrades to a retry state). Image preview failures fall
back to the binary notice.

## Testing

- Infra: real-git fixtures for scripted interactive rebase (reorder,
  squash with message, fixup, drop), `getFileBytes` (HEAD/index/worktree),
  compare rev-list counts.
- Application: pure tests for `buildRebaseTodo` + validation,
  `buildFileTree`; GitHubApi REST impl against a fake `http.Client`
  (status codes → typed errors).
- UI: controller tests for new facade methods; widget tests for the
  rebase editor (reorder + action selection), GitHub panel states
  (loading/empty/error/CTA), tree toggle.
- S4 is visual: rely on the existing widget-test suite for regressions;
  no goldens.
