# Changelog

All notable changes to GitOpen are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Each release maps to a
`v*` Git tag — the same tags the in-app updater checks.

## [1.5.1] — 2026-06-18

### Fixed
- **Testing a saved credential now actually validates it.** The "Test" button
  previously ran an anonymous `git ls-remote https://github.com` against the
  host root — which always failed with "repository not found" and never even
  used the token. It now authenticates the profile's token against the GitHub
  API (`GET /user`): success reports the authenticated login (and warns if it
  differs from the profile's username), and failures report the real reason
  (401 invalid token, 403 scope/rate-limit, network error).
- The **About** page showed a stale hard-coded `0.3.0-dev`; it now reads the
  running version from the app package.

### Changed
- GitHub sign-in via OAuth Device Flow now requests `repo read:org user:email`
  instead of `repo` alone. The added `user:email` scope lets the per-folder
  identity resolver match an account by its verified emails, and `read:org`
  exposes organization repositories — so logging in with GitHub is now a full
  alternative to a manually created PAT.
- The branches/remotes/tags sidebar is now hidden while the Settings page is
  open, giving settings the full window width.

## [1.5.0] — 2026-06-18

### Added
- A **Repository** info panel, opened from the info button next to the active
  repo name in the title bar. It shows the repo's local folder path, its
  `origin` remote URL, and the effective git identity (user name and email)
  for that repo. Each row has a copy button; the path can be opened in the
  file manager and the origin URL opened in the browser.

## [1.4.1] — 2026-06-18

### Fixed
- The update check no longer reports "You are up to date" when the check
  actually failed. A non-200 from GitHub (rate limit, offline, server error)
  now surfaces a real error instead of masquerading as current.
- Update checks are now authenticated with a saved GitHub token when one
  exists (5000 req/h) instead of the shared 60 req/h unauthenticated per-IP
  limit — which is easily exhausted behind a corporate NAT, the reason the
  check kept failing.

## [1.4.0] — 2026-06-18

### Added
- Ahead/behind badges (`↑ to push ↓ to pull`) on diverged local branches in
  the sidebar and next to the active repo name in the title bar.
- A modal overlay blocks interaction while a git operation runs (fetch, pull,
  push, checkout, merge, rebase, …) so you can't navigate or start another
  action mid-operation; network operations show a Cancel button that aborts the
  underlying git process.

### Changed
- `git fetch` now prunes — remote branches deleted on the server (e.g. after a
  merged PR) no longer linger in the sidebar.

### Fixed
- Remote-branch ahead/behind parsing (a latent all-optional regex always
  reported 0/0).

## [1.3.0] — 2026-06-18

### Added
- Delete a branch's local and remote side together. The branch context menu's
  **Delete** now opens a dialog with a checkbox for the local branch and one
  for its tracked remote branch (both checked by default when present); the
  local checkbox is disabled when it is the checked-out branch. Deleting the
  remote runs `push --delete` through the authenticated path (so it works with
  the right account), and an unmerged local branch offers a force retry. Works
  from both a local branch (deletes its upstream too) and a remote branch
  (deletes the tracking local too).

## [1.2.2] — 2026-06-17

### Fixed
- Settings is now reachable when no repository is open. With an empty catalog
  the main area always showed the welcome screen, so the Settings button
  toggled its state but the page never appeared — leaving no way to reach
  Settings → Updates (or anything else) without first opening a repo. Settings
  now takes precedence over the empty/welcome state.
- Opening a repository (and "Open folder of repositories") works again. The
  repo dropdown dismissed itself before the folder picker returned, which
  disposed the popover; the code then used the disposed widget to finish
  opening, so the pick silently did nothing. The needed services are now read
  before dismissing, so the repo is added after you choose a folder.

## [1.2.1] — 2026-06-17

### Fixed
- "Open folder of repositories" now scans recursively, so it finds repos
  grouped under intermediate folders (e.g. `repos/Personal/<repo>`,
  `repos/Novomatic/<repo>`). The previous scan only looked one level deep and,
  combined with a silent per-repo error skip, opened nothing with no message.
  It does not descend into a repo (so submodules aren't listed) and skips
  hidden dirs and `node_modules`.

### Changed
- Repository and folder rows in the repo dropdown now have a direct trash
  button (with a confirmation) instead of a three-dots menu. Folders can now
  be removed too — their contents move up one level. Removal is
  non-destructive: nothing is deleted from disk.

## [1.2.0] — 2026-06-17

### Added
- Accounts now record the emails GitHub knows for them, auto-populated on
  sign-in and refreshable from Settings → Authentication (with manual
  add/remove). When several accounts share a host, a repository's effective git
  `user.email` — e.g. set per-folder via `.gitconfig` `includeIf` — automatically
  selects the matching account for fetch/push, with no per-repo binding needed.
  Resolution order: explicit per-repo choice → email match → single account per
  host → prompt.

## [1.1.2] — 2026-06-17

### Changed
- Internal refactor: split the two largest UI files into focused units —
  `file_row.dart` → `hunk_row.dart` + `state_badge.dart` + a `FileRowActions`
  controller; `commit_graph_panel.dart` → `commit_graph_providers.dart` +
  `commit_graph_search_field.dart`. No user-facing change.

## [1.1.1] — 2026-06-17

### Fixed
- Remotes and their branches now appear in the sidebar. `getRemotes` parsed
  `git remote -v` expecting a second TAB before `(fetch)`, but git writes a
  SPACE there — so every line was skipped and the REMOTES section always showed
  "Add remote…" even with a configured remote. Now splits the line on the last
  space.

## [1.1.0] — 2026-06-17

### Repository organization
- The repository dropdown is now a **persistent catalog**: every repo you have
  opened stays listed and organized, and a single active repo is restored on
  launch (replacing the old per-session open set).
- Organize repositories into **nested folders** and **reorder** them by drag &
  drop — drag a repo within or between folders, drop onto a folder to file it
  inside, and reorder or reparent the folders themselves. The tree, collapse
  state and order persist across restarts.
- "Close" became **Remove from GitOpen**, which forgets a repo from the catalog
  without touching the working copy on disk. Removing a folder is
  non-destructive: its contents move up to the parent folder.

## [1.0.6] — 2026-06-17

### Performance
- Auto-refresh now refreshes only what changed. A fetch or window focus-regain
  no longer re-logs the whole commit graph or re-reads every ref: the file
  watcher classifies the changed `.git` path (HEAD / refs / fetch / merge
  state) and only the affected providers are invalidated, and focus-regain
  refreshes the working-tree status (with a HEAD-moved safety net) instead of
  the entire read layer. Noticeably less work on large repos when alt-tabbing.

## [1.0.5] — 2026-06-17

### Changed
- Internal: the reflog dialog no longer rebuilds its `git reflog` future on
  every widget rebuild (the future is created once), matching the codebase's
  provider/Future conventions. No user-facing behaviour change.

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
