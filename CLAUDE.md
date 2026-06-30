# GitOpen

Fast, cross-platform open-source **desktop git client** built with Flutter.
Wraps the system `git` CLI for every operation (no libgit2). Targets **Windows**
and **Linux**. Repo: `github.com/zN3utr4l/GitOpen` (a fork of `samuu98/GitOpen`).

## Quick Start

```powershell
# Windows (PowerShell)
flutter pub get
.\run.ps1            # debug run on Windows desktop  (= flutter run -d windows)
.\run.ps1 test      # flutter test
.\run.ps1 analyze   # flutter analyze
.\run.ps1 clean     # flutter clean + pub get
```

```bash
# Linux
flutter pub get
flutter run -d linux
```

A working `git` on `PATH` is required at runtime. Dart SDK `^3.11.5`
(Flutter stable). After pulling schema changes, regenerate drift code:
`dart run build_runner build --delete-conflicting-outputs`.

## Architecture

Clean layering — **`domain` / `application` / `infrastructure` / `ui`**:

- **`lib/domain/`** — pure value types (commits, diffs, refs, status, files). No I/O.
- **`lib/application/`** — use cases, Riverpod providers, ports (interfaces).
  Pure: `dart:io` does **not** appear here except the composition root
  `lib/application/providers.dart`.
- **`lib/infrastructure/`** — adapters that touch the outside world: the `git`
  CLI runners/parsers, drift database, GitHub REST, file watchers. `dart:io`
  lives here.
- **`lib/ui/`** — Flutter widgets (shell, sidebar, toolbar, commit graph, diff,
  dialogs, settings). Riverpod `ConsumerWidget`s.

State is managed with **Riverpod 3**, persistence with **drift** (SQLite),
the chromeless window with **bitsdojo_window**. All git work goes through the
user's `git` CLI via `GitActionsService`/`GitActionsController`.

See `.claude/memory/project-map.md` for the module map and
`.claude/memory/gotchas.md` for landmines before editing.

## Conventions

- **Lint:** `very_good_analysis`. `flutter analyze` is **fatal on any issue
  including `info`**, and it covers `test/` too. Always run **bare
  `flutter analyze`** (whole project) before pushing — not per-file.
- **Format:** `dart format`, but **do NOT blanket-format**. This repo predates
  the Dart 3.12 tall-style formatter, so `dart format lib test` rewrites ~180
  files. Format only files you touched, or do a dedicated chore PR. (This is why
  there is no format-on-save hook.)
- **Generated files** (`*.g.dart`, `*.freezed.dart`) are analyzer-excluded; never
  hand-edit them — change the source and re-run `build_runner`.
- **Tests:** `flutter test` (unit + widget). Widgets that watch
  `appSettingsProvider` must override it in tests or the real drift DB is built.

## Build & packaging

- Windows installer: `flutter build windows --release` + Inno Setup
  (`installer/windows/gitopen.iss`); msix config lives in `pubspec.yaml`.
- Linux `.deb`: `bash scripts/build-deb.sh`.
- CD builds release artifacts on every tagged release; the PR gate runs only
  `flutter analyze` + `flutter test` and does **not** compile native runners or
  the installer.

## Git workflow

- `main` is **PR-gated** (strict required checks + enforce_admins). The required
  check is `build-and-test (ubuntu-latest)`. When `lib/` changes, `version-check`
  expects a new unreleased `x.y.z` in `pubspec.yaml`; CD releases `v<version>` on
  merge.
- Commits use the **zN3utr4l** identity (configured via git `includeIf`). Verify
  before pushing.
- **Remotes** (re-pointed once the fork became canonical): `origin` =
  **samuu98/GitOpen** — the repo you work on; local `main` tracks `origin/main`.
  `fork` = **zN3utr4l/GitOpen** — the personal fork. Pass `--repo samuu98/GitOpen`
  to `gh` commands. PRs are **cross-fork**: push the branch to `fork`, then
  `gh pr create --repo samuu98/GitOpen --base main --head zN3utr4l:<branch>`.
  `samuu98` pushes occasionally, so `git fetch origin` and branch off a fresh
  `origin/main` (don't `git pull` blindly — check the tracking branch first).

---

`AGENTS.md` is a byte-for-byte copy of this file (some tools read `AGENTS.md`).
The versioned `.githooks/pre-commit` hook auto-regenerates `AGENTS.md` from the
**staged** `CLAUDE.md` at commit time (requires `git config core.hooksPath
.githooks`, set once per clone) — so just edit `CLAUDE.md` and `git add` it; no
manual `cp` needed.
