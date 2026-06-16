# Phase 5 — S5 Showcase v1.0.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task (inline; this repo's owner wants no subagent
> dispatch). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship GitOpen v1.0.0 — a showcase README + CHANGELOG, corrected branding
across the Windows/Linux installers and embedded metadata, and a pubspec bump that
makes CD publish the public `v1.0.0` release.

**Architecture:** S5 is the final slice of the Phase 5 "Complete & Beautiful"
roadmap (`docs/superpowers/specs/2026-06-11-phase5-complete-beautiful-design.md`).
S1–S4 are merged (v0.1.18 → v0.1.29). This slice touches no Dart logic — it is
documentation + packaging/branding metadata + the version bump. Bumping
`pubspec.yaml` (plus the `windows/`, `scripts/`, `installer/` edits) trips the CD
path filter, so merging to `main` auto-builds the Inno installer + `.deb` and
publishes a GitHub Release tagged `v1.0.0`.

**Tech Stack:** Flutter/Dart (no code change here), Inno Setup (Windows installer),
`dpkg-deb` (.deb), GitHub Actions CI/CD, Keep a Changelog format.

**Owner decisions (2026-06-16):**
- README ships **text-only** for v1.0.0 (feature matrix + status badges, no
  screenshots/GIF). Visuals can land later in a docs-only PR (docs don't trigger CD).
- **Full auto** release: open the PR, wait for green CI, merge to `main`, let CD
  publish v1.0.0.

---

## Critical context / hazards (read before executing)

1. **The local `v1.0.0` git tag is NOT ours.** It points to `upstream/main`
   (samuu98/GitOpen, the fork parent), pulled in by a past `git fetch upstream`.
   Origin (`zN3utr4l/GitOpen`) does **not** have a `v1.0.0` tag. CD checks origin
   via `git ls-remote`, so it will correctly build and create `v1.0.0` on our merge
   commit. **Never `git push --tags`** or push the tag explicitly — pushing the
   upstream `v1.0.0` to origin would make CD see "already released" and skip the
   build. Task 0 deletes the local tag defensively.
2. **gh account flips to the work account** (`giuseppe-chirico`) between commands,
   causing 403 on push/merge. Run
   `gh auth switch --hostname github.com --user zN3utr4l` in the **same** command
   immediately before each push/merge, and retry if it flips again.
3. **Always pass `--repo zN3utr4l/GitOpen`** to gh commands.
4. **Never `git pull` without checking tracking** — an `upstream` remote exists and
   a bare pull once started a huge upstream merge. Use `git fetch origin` +
   explicit refs. Local `main` currently equals `origin/main` (verified).
5. **No blanket `dart format`** (pre-tall-style codebase). S5 changes no `.dart`
   files anyway.
6. **Branch protection:** `main` is PR-gated, strict + enforce_admins. Required
   checks: `build-and-test` (windows + ubuntu) and `version-check`. Must be green
   before merge; admin cannot bypass. Branch must be up to date with main (it will
   be — no concurrent work).
7. **Flutter is not on PATH:** `C:\Users\g.chirico\flutter\bin\flutter.bat`. Run
   `flutter analyze` / `flutter test` from the repo dir.

---

## File structure

- `CHANGELOG.md` — **create** (repo root). Summarizes 0.1 → 1.0.
- `README.md` — **rewrite** (repo root). Stale (says "Slice 2 complete", MSIX/
  AppImage, references a non-existent `scripts/build-appimage.sh`).
- `CONTRIBUTING.md` — **fix** (repo root). Contains .NET leftovers (`dotnet test`,
  bUnit).
- `windows/runner/Runner.rc` — **modify**. Embedded EXE version-info still has the
  template defaults (`ProductName "gitopen"`, `CompanyName "com.gitopen"`).
- `installer/windows/gitopen.iss` — **modify**. Wire `SetupIconFile` to the existing
  `app_icon.ico` (wizard currently uses the default Inno icon).
- `scripts/build-deb.sh` — **modify**. `Homepage` points at the non-existent
  `github.com/sporta/GitOpen`; maintainer is the work email.
- `pubspec.yaml` — **modify**. `version: 0.1.29+30` → `1.0.0+31`.

No tests change (no Dart logic touched). Verification = `flutter analyze` +
`flutter test` stay green, then CI on the PR.

---

## Task 0: Branch + defensive tag cleanup

**Files:** none (git state only)

- [ ] **Step 1: Confirm clean state on main, synced with origin**

```bash
cd /d/repos/Personal/GitOpen
git status -sb            # expect: ## main...origin/main  (no ahead/behind, clean)
git fetch origin          # explicit; do NOT `git pull`
```
Expected: working tree clean, `main` even with `origin/main`.

- [ ] **Step 2: Delete the stray local upstream `v1.0.0` tag (local only, safe)**

```bash
git tag -d v1.0.0
```
Expected: `Deleted tag 'v1.0.0' (was f1d9f72)`. (Origin is untouched; this only
removes the confusing local pointer to the upstream commit.)

- [ ] **Step 3: Create the slice branch**

```bash
git switch -c chore/phase5-s5-showcase-v1.0.0
```
Expected: `Switched to a new branch 'chore/phase5-s5-showcase-v1.0.0'`.

---

## Task 1: CHANGELOG.md (summarize 0.1 → 1.0)

**Files:**
- Create: `CHANGELOG.md`

- [ ] **Step 1: Create `CHANGELOG.md` with the full content below**

```markdown
# Changelog

All notable changes to GitOpen are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Each release maps to a
`v*` Git tag — the same tags the in-app updater checks.

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
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add CHANGELOG summarizing 0.1 to 1.0"
```

---

## Task 2: Rewrite README.md (text-only showcase)

**Files:**
- Modify (full replace): `README.md`

- [ ] **Step 1: Replace the entire `README.md` with the content below**

```markdown
# GitOpen

[![CI](https://github.com/zN3utr4l/GitOpen/actions/workflows/ci-gitopen.yml/badge.svg)](https://github.com/zN3utr4l/GitOpen/actions/workflows/ci-gitopen.yml)
[![Latest release](https://img.shields.io/github/v/release/zN3utr4l/GitOpen?sort=semver)](https://github.com/zN3utr4l/GitOpen/releases/latest)
[![Platforms](https://img.shields.io/badge/platforms-Windows%20%7C%20Linux-blue)](https://github.com/zN3utr4l/GitOpen/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A fast, cross-platform open-source **desktop git client** built with Flutter.
GitOpen wraps the system `git` CLI for every operation and presents a Fork-inspired
graph view, full history and branch tooling, conflict resolution, and GitHub
integration in a chromeless native window. Targets **Windows** and **Linux**.

> Fork maintained by [zN3utr4l](https://github.com/zN3utr4l), based on the original
> [GitOpen](https://github.com/samuu98/GitOpen) by s.porta (MIT).

## Install

Grab the latest build from the
[**Releases**](https://github.com/zN3utr4l/GitOpen/releases/latest) page.

**Windows** — download `GitOpen-Setup-<version>.exe` and run it (per-user install,
no admin required).
> The installer is not code-signed yet, so Windows SmartScreen may warn on first
> run — click **More info → Run anyway**. GitOpen can update itself afterwards from
> **Settings → Updates**.

**Linux (Debian/Ubuntu)** — download `gitopen_<version>_amd64.deb` and install it:
```bash
sudo apt install ./gitopen_<version>_amd64.deb
```
This pulls in `libgtk-3-0`, `libstdc++6`, `libc6`, and `git`, and adds a `gitopen`
command plus a desktop entry.

A working `git` on `PATH` is required at runtime on both platforms.

## Features

| Area | Capabilities |
| --- | --- |
| **Graph & history** | Colour-coded multi-lane commit graph, incremental loading on scroll, co-author avatars, reflog viewer, compare-refs (ahead/behind + combined diff), GPG signature badges |
| **Diff & viewer** | Unified and side-by-side diffs, intraline word-diff, ignore-whitespace toggle, image diff (old/new preview), large-diff cap with load-full, blame / file history, flat or tree file lists |
| **Staging & commit** | File-, hunk-, and line-level staging; line/hunk unstage and discard; amend; sign-off; `Ctrl+Enter`; per-file use-ours / use-theirs |
| **Branches & remotes** | Branch CRUD, tracking-branch checkout, fetch / pull / push with streaming progress, push split-button (force-with-lease, tags, branch picker) |
| **History ops** | Full interactive rebase (reorder, pick/reword/squash/fixup/drop, multiline editor), reword & edit-at-commit, cherry-pick, revert, undo last commit |
| **Stash & worktrees** | Stash save / apply / pop / list, preview and partial stash, worktree add / list / remove, repo init, annotated tags, Git LFS support |
| **GitHub** | OAuth Device Flow sign-in, clone public/private, Pull Requests panel (checkout, review comments, PR mutations), Actions workflow-run panel |
| **Experience** | Light / dark themes, customizable keybindings, status bar (branch + ahead/behind + running ops), activity toasts, auto-refresh `.git` watcher, in-app updater, accessibility passes |

## Build and run

Prerequisites:
- Flutter SDK (stable channel) — Dart `^3.11.5`
- `git` CLI on `PATH` (Git for Windows on Windows; `apt install git` on Ubuntu)
- **Windows:** Visual Studio 2022 with the "Desktop development with C++" workload
- **Linux:** `sudo apt install clang cmake ninja-build libgtk-3-dev liblzma-dev`

```powershell
# Windows
flutter pub get
flutter run -d windows
```

```bash
# Linux
flutter pub get
flutter run -d linux
```

## Tests

```bash
flutter test       # unit + widget suite
flutter analyze    # static analysis (very_good_analysis)
```

## Packaging

CD builds release artifacts automatically on every tagged release. To build them
locally:

```bash
# Linux .deb (outputs build/gitopen_<version>_amd64.deb)
bash scripts/build-deb.sh

# Windows installer (requires Inno Setup 6)
flutter build windows --release
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" /DAppVersion=<version> installer\windows\gitopen.iss
```

## Architecture

Clean layering — `application` / `domain` / `infrastructure` / `ui` — with all git
work going through the system `git` CLI (no libgit2). State is managed with Riverpod
and persisted with Drift (SQLite); the chromeless window uses `bitsdojo_window`.
`dart:io` is confined to the infrastructure layer and the composition root. See
`docs/superpowers/specs/` for designs and `docs/superpowers/plans/` for the
slice-by-slice implementation plans, and `CHANGELOG.md` for the release history.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README for the v1.0.0 showcase release"
```

---

## Task 3: Fix CONTRIBUTING.md (.NET leftovers → Flutter/Dart)

**Files:**
- Modify (full replace): `CONTRIBUTING.md`

- [ ] **Step 1: Replace the entire `CONTRIBUTING.md` with the content below**

```markdown
# Contributing

GitOpen is open source under the MIT license. Contributions are welcome.

## Development setup

See [`README.md`](README.md) for prerequisites and how to build and run. Before
submitting a PR, make sure the suite is green:

```bash
flutter analyze
flutter test
```

## Architecture

See `docs/superpowers/specs/` for the designs and `docs/superpowers/plans/` for the
slice-by-slice implementation plans.

## Conventions

- TDD on the Application and Infrastructure layers; widget tests for UI.
- [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `docs:`, `test:`, `chore:`, `ci:`, `build:`, `perf:`).
- One logical change per commit; keep files focused (one responsibility per file).
- `main` is PR-gated. App-code changes must bump `version` in `pubspec.yaml`; CD
  publishes `v<version>` on merge.
```

- [ ] **Step 2: Commit**

```bash
git add CONTRIBUTING.md
git commit -m "docs: correct CONTRIBUTING for the Flutter/Dart toolchain"
```

---

## Task 4: Brand the Windows EXE version-info + installer icon

**Files:**
- Modify: `windows/runner/Runner.rc:92-99`
- Modify: `installer/windows/gitopen.iss:30-32`

- [ ] **Step 1: Update the `StringFileInfo` block in `windows/runner/Runner.rc`**

Replace the existing block (lines ~92–99):

```
            VALUE "CompanyName", "com.gitopen" "\0"
            VALUE "FileDescription", "gitopen" "\0"
            VALUE "FileVersion", VERSION_AS_STRING "\0"
            VALUE "InternalName", "gitopen" "\0"
            VALUE "LegalCopyright", "Copyright (C) 2026 com.gitopen. All rights reserved." "\0"
            VALUE "OriginalFilename", "gitopen.exe" "\0"
            VALUE "ProductName", "gitopen" "\0"
            VALUE "ProductVersion", VERSION_AS_STRING "\0"
```

with:

```
            VALUE "CompanyName", "GitOpen" "\0"
            VALUE "FileDescription", "GitOpen - cross-platform desktop git client" "\0"
            VALUE "FileVersion", VERSION_AS_STRING "\0"
            VALUE "InternalName", "gitopen" "\0"
            VALUE "LegalCopyright", "Copyright (C) 2026 s.porta & zN3utr4l. MIT License." "\0"
            VALUE "OriginalFilename", "gitopen.exe" "\0"
            VALUE "ProductName", "GitOpen" "\0"
            VALUE "ProductVersion", VERSION_AS_STRING "\0"
```
(`InternalName` / `OriginalFilename` stay `gitopen` / `gitopen.exe` — they match the
actual binary name set in CMake.)

- [ ] **Step 2: Wire the installer wizard icon in `installer/windows/gitopen.iss`**

Replace the comment block at the end of `[Setup]` (lines ~30–32):

```
; Inno Setup requires a .ico for SetupIconFile; assets ship only a .png,
; so we leave the default installer icon for now. Add a .ico under
; assets/icon/ later and set SetupIconFile= to embed a custom one.
```

with:

```
; Brand the installer wizard with the app icon. Inno needs a .ico; reuse the
; one the Flutter Windows runner already embeds in the executable.
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
```
(The `.iss` lives in `installer/windows/`, so `..\..` is the repo root, then
`windows\runner\resources\app_icon.ico` — the file confirmed to exist.)

- [ ] **Step 3: Sanity-check the icon path exists**

```bash
ls -la /d/repos/Personal/GitOpen/windows/runner/resources/app_icon.ico
```
Expected: the file is listed.

- [ ] **Step 4: Commit**

```bash
git add windows/runner/Runner.rc installer/windows/gitopen.iss
git commit -m "build(win): brand EXE version-info and installer wizard icon"
```

---

## Task 5: Fix the .deb branding (homepage + maintainer)

**Files:**
- Modify: `scripts/build-deb.sh:60-61`

- [ ] **Step 1: Update the `Maintainer` and `Homepage` lines in `scripts/build-deb.sh`**

Replace:

```
Maintainer: s.porta <s.porta@novomatic.it>
Homepage: https://github.com/sporta/GitOpen
```

with:

```
Maintainer: s.porta & zN3utr4l <zN3utr4l@users.noreply.github.com>
Homepage: https://github.com/zN3utr4l/GitOpen
```
(Fixes the non-existent `sporta/GitOpen` URL and drops the work email; credits both
the original author and the fork maintainer, matching the Windows installer's
`AppPublisher`.)

- [ ] **Step 2: Verify the heredoc still parses (bash syntax check, no build)**

```bash
bash -n /d/repos/Personal/GitOpen/scripts/build-deb.sh && echo "syntax OK"
```
Expected: `syntax OK`.

- [ ] **Step 3: Commit**

```bash
git add scripts/build-deb.sh
git commit -m "build(linux): fix .deb homepage URL and maintainer branding"
```

---

## Task 6: Bump pubspec to 1.0.0

**Files:**
- Modify: `pubspec.yaml:4`

- [ ] **Step 1: Bump the version**

Replace:

```
version: 0.1.29+30
```

with:

```
version: 1.0.0+31
```
(`msix_config.msix_version` is already `1.0.0.0` — no change needed there.)

- [ ] **Step 2: Commit**

```bash
git add pubspec.yaml
git commit -m "chore: bump version to 1.0.0"
```

---

## Task 7: Verify locally

**Files:** none

- [ ] **Step 1: Static analysis is clean**

```bash
cd /d/repos/Personal/GitOpen
"C:/Users/g.chirico/flutter/bin/flutter.bat" analyze
```
Expected: `No issues found!` (no `.dart` changed, so this should match the prior
baseline).

- [ ] **Step 2: Test suite is green**

```bash
"C:/Users/g.chirico/flutter/bin/flutter.bat" test
```
Expected: all tests pass (683 green per the S4 baseline; S5 touches no Dart).

---

## Task 8: Push, open PR, wait for CI

**Files:** none

- [ ] **Step 1: Push the branch (handle the gh auth flip in the same command)**

```bash
gh auth switch --hostname github.com --user zN3utr4l && git push -u origin chore/phase5-s5-showcase-v1.0.0
```
> Do **not** add `--tags`. If push 403s, re-run the `gh auth switch && git push`
> line.

- [ ] **Step 2: Open the PR**

```bash
gh auth switch --hostname github.com --user zN3utr4l && gh pr create --repo zN3utr4l/GitOpen \
  --base main --head chore/phase5-s5-showcase-v1.0.0 \
  --title "S5: showcase v1.0.0" \
  --body "Phase 5 S5 — the showcase release.

- CHANGELOG summarizing 0.1 -> 1.0
- README rewritten (text-only: feature matrix + badges + install/build); visuals to follow in a docs-only PR
- CONTRIBUTING corrected for the Flutter/Dart toolchain
- Windows EXE version-info + installer wizard icon branded
- .deb homepage URL + maintainer fixed
- pubspec -> 1.0.0+31 (CD publishes v1.0.0 on merge)

Closes Phase 5 (spec 2026-06-11-phase5-complete-beautiful-design.md)."
```

- [ ] **Step 3: Wait for required checks to pass**

```bash
gh pr checks --repo zN3utr4l/GitOpen --watch
```
Expected: `build-and-test (windows-latest)`, `build-and-test (ubuntu-latest)`, and
`version-check` all pass. (`version-check` confirms `1.0.0` > `0.1.29` and that
origin has no `v1.0.0` tag.)

---

## Task 9: Merge and let CD publish v1.0.0

**Files:** none

- [ ] **Step 1: Merge with a merge commit (matches the repo's history style)**

```bash
gh auth switch --hostname github.com --user zN3utr4l && gh pr merge --repo zN3utr4l/GitOpen --merge --delete-branch
```
> If it 403s on the auth flip, re-run the same line. Do not use `--admin` to bypass
> failing checks — wait for green first (Task 8).

- [ ] **Step 2: Confirm CD started**

```bash
gh auth switch --hostname github.com --user zN3utr4l && gh run list --repo zN3utr4l/GitOpen --workflow cd-release.yml --limit 3
```
Expected: a `CD Release` run for the merge commit is queued/in-progress.

- [ ] **Step 3: Watch CD to completion**

```bash
gh run watch --repo zN3utr4l/GitOpen $(gh run list --repo zN3utr4l/GitOpen --workflow cd-release.yml --limit 1 --json databaseId --jq '.[0].databaseId')
```
Expected: the `version` → `build-windows` / `build-linux` → `release` jobs all
succeed. (`version` resolves `1.0.0`, sees no `v1.0.0` on origin → `released=false`
→ builds and releases.)

- [ ] **Step 4: Verify the public release exists with both artifacts**

```bash
gh release view v1.0.0 --repo zN3utr4l/GitOpen
```
Expected: `GitOpen v1.0.0` with `GitOpen-Setup-1.0.0.exe` and
`gitopen_1.0.0_amd64.deb` attached, and a `v1.0.0` tag on the merge commit.

- [ ] **Step 5: Sync local main (explicit, no bare pull)**

```bash
git switch main && git fetch origin && git merge --ff-only origin/main
```
Expected: local `main` fast-forwards to the merge commit.

---

## Self-review

- **Spec coverage (S5 = README, CHANGELOG, installer branding check, pubspec→1.0.0):**
  - README rewritten → Task 2 (text-only per owner decision; screenshots deferred,
    noted in PR body).
  - CHANGELOG 0.1 → 1.0 → Task 1.
  - Installer branding check (icon, app name, publisher) → Task 4 (Windows
    version-info + wizard icon) and Task 5 (.deb). Windows `.iss` publisher and
    `msix` publisher were already correct (`s.porta & zN3utr4l`, from PR #41); this
    slice closes the remaining gaps (lowercase EXE metadata, default wizard icon,
    wrong `.deb` homepage). CONTRIBUTING fix (Task 3) is an adjacent showcase-quality
    correction.
  - `pubspec.yaml` → `1.0.0` and CD publishes v1.0.0 → Task 6 + Task 9.
- **Placeholders:** none — every file's full final content or exact replacement is
  inline.
- **Consistency:** version `1.0.0+31` used in pubspec; `v1.0.0` tag/release name
  used consistently; publisher string `s.porta & zN3utr4l` matches across `.iss`
  (existing), `Runner.rc`, and `.deb`. CD path filter confirmed to include
  `pubspec.yaml`, `windows/**`, `installer/**`, `scripts/**` (the files touched here
  that must trigger a build).
```
