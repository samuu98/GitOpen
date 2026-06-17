# Changelog

All notable changes to GitOpen are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Each release maps to a
`v*` Git tag — the same tags the in-app updater checks.

## [1.0.4] — 2026-06-17

### Fixed
- Panels no longer flicker to a spinner (content briefly disappearing) when an
  auto-refresh runs — on every fetch and whenever the window regains focus.
  Affected the sidebar, status-bar branch name, working-copy change list, file
  diff preview, commit details/diff, the graph's uncommitted-changes row, and
  the conflict panel: each now keeps its current content visible while the
  reload happens in the background (`skipLoadingOnReload`), matching the commit
  graph. Root cause: `AsyncValue.when()` re-shows its `loading` builder on every
  dependency-triggered reload, and the auto-refresh invalidates the shared git
  read layer those panels watch.

## [1.0.0] — 2026-06-16

First stable release. GitOpen is a cross-platform (Windows + Linux) desktop git
client built with Flutter that wraps the system `git` CLI. 1.0.0 closes the
"Complete & Beautiful" phase: full interactive rebase, rich diff/viewer tooling,
GitHub pull-request and Actions integration, an in-app updater, and a deeply
polished, tokenized design language.

This release summarizes the entire `0.1.x` series. Notable capabilities:

### Repository viewing
- Commit graph with multi-branch colour-coded lanes, incremental loading
  (300 commits per page, grown on scroll) and overlapping co-author avatar stacks.
- Branch / tag / remote / stash / worktree sidebar tree with a folder hierarchy.
- Multi-repo tabs persisted across restarts.
- Commit details with a unified **and** side-by-side diff, intraline word-diff,
  ignore-whitespace toggle, large-diff cap with "load full diff", image diff
  (old/new preview), a flat/tree file-list toggle, blame / file history, and a
  reflog viewer.
- Compare any two refs: ahead/behind counts plus the combined diff.
- GPG signature badges on signed commits.

### Staging & committing
- File-level, hunk-level, and line-level staging; line-level and hunk-level
  unstage and discard.
- Amend, sign-off, and a `Ctrl+Enter` commit shortcut.
- Per-file "use ours / use theirs" during conflicts.

### History & branch operations
- Branch CRUD, tracking-branch checkout, and guarded checkout at every entry point.
- Fetch / pull / push with streaming progress; a push split-button
  (force-with-lease, push tags, branch picker).
- Merge with a dedicated conflict-resolution panel (continue / abort), cherry-pick,
  revert, and undo-last-commit (soft reset).
- Full interactive rebase: reorder, pick / reword / squash / fixup / drop, with a
  multiline message editor; reword and edit-at-commit.
- Stash save / apply / pop / list plus stash preview and partial stash.
- Repository init, annotated tag creation, and worktree add / list / remove.
- Git LFS daily-driver support.

### GitHub integration
- OAuth Device Flow sign-in with a secure token store; clone public and private
  repositories.
- Pull Requests panel: list, per-PR checkout, open in browser, plus a PR workbench
  for review comments and PR mutations.
- Actions panel: recent workflow runs with status, conclusion, and duration.

### Experience & distribution
- Settings (General, Auth, Keybindings, GitHub, Updates, About) with light and dark
  themes and customizable keybindings.
- Status bar (current branch, ahead/behind, running operations) and an activity
  panel with progress toasts.
- Repository auto-refresh via a `.git` watcher that filters transient index noise.
- In-app updater that downloads and launches the latest release installer.
- Accessibility passes across the graph, sidebar, and working-copy surfaces;
  detached-HEAD banner and empty-state calls to action.
- Windows Inno Setup installer (`.exe`) and Linux `.deb` package, published
  automatically by CD on every tagged release.

### Notes
- GitOpen is a fork maintained by [zN3utr4l](https://github.com/zN3utr4l), based on
  the original [GitOpen](https://github.com/samuu98/GitOpen) by s.porta, under the
  MIT license.

## 0.1.x series (2026-06)

The `0.1.1` → `0.1.29` releases built GitOpen up from a read-only viewer to a
full-featured client through a debt-first refactor program and four roadmap
phases (clean application / domain / infrastructure / UI layering, the write-
operation facade, the post-program audit, and the Phase 5 pillars above). See the
GitHub releases for `v0.1.1` … `v0.1.29` and `docs/superpowers/` for the specs and
slice-by-slice plans.
