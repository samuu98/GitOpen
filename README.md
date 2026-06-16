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
