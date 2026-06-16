# Open a Folder of Repositories — Design

**Date:** 2026-06-16
**Status:** approved
**Owner:** zN3utr4l

## Context

Opening repositories is one-at-a-time: `RepoSelector` (title-bar dropdown) →
"Open repository..." → `folderPickerProvider.pickFolder` → `workspaceManager.open(path)`.
Users with a container folder (e.g. `D:\repos\Personal`) must open each child repo
manually. Goal: pick the container folder once and open every git repo inside it.

`DriftRepositoryRegistry.add(path)` does **not** validate that a path is a git repo —
it just records it. So discovery must filter to real repositories before opening; we
cannot rely on `open` to reject non-repos.

Scope decision (owner 2026-06-16): scan **immediate subdirectories only** (depth 1),
not recursive.

## Goal

A "Open folder of repos..." action: pick a parent folder, open every immediate
subdirectory that is a git repository as a workspace tab, select the first newly
opened one, and report when none are found.

## Components

- **Port** `lib/application/launcher/repo_folder_scanner.dart`:
  ```dart
  abstract interface class RepoFolderScanner {
    /// Git repositories that are immediate subdirectories of [parentPath].
    Future<List<String>> findRepositories(String parentPath);
  }
  ```
- **Infrastructure** `lib/infrastructure/launcher/io_repo_folder_scanner.dart`
  (`IoRepoFolderScanner`): lists the immediate subdirectories of `parentPath` and keeps
  those containing a `.git` entry (a directory for normal clones, or a file for
  worktrees/submodules). Returns absolute paths sorted by name; returns `[]` when the
  parent does not exist. `dart:io` lives here, per the layering rule.
- **Provider** `repoFolderScannerProvider` in `lib/application/providers.dart`:
  `Provider<RepoFolderScanner>((ref) => const IoRepoFolderScanner())` (mirrors
  `gitDirProbeProvider`/`folderPickerProvider`).
- **UI** `lib/ui/shell/repo_selector.dart`: a new "Open folder of repos..." menu item
  next to "Open repository..." → `pickFolder` → `scanner.findRepositories` → open each
  via `workspaceManager.open` (which dedups already-open repos by id) → set the active
  workspace to the first newly opened repo → if the list is empty, show a SnackBar
  ("No git repositories found in <folder>").

Each unit has one job: the scanner discovers, the manager opens/dedups, the UI wires
the picker → scan → open → select.

## Data flow

pick folder → `findRepositories(parent)` → `[repoPathA, repoPathB, …]` → for each,
`workspaceManager.open(path)` (dedup) → first opened workspace becomes active.

## Error handling

- Parent missing / unreadable → scanner returns `[]` → UI shows "no repositories
  found".
- A single `open` failure is logged and skipped so the rest still open (loop catches
  per-path, like `_rehydrate`).
- Empty result → non-blocking SnackBar, no tabs opened.

## Release

Touches `lib/**` → `version-check` + CD. Bump `pubspec.yaml` `1.0.2+33` → `1.0.3+34`;
CD publishes **v1.0.3**.

## Testing

- **Infrastructure (fixture):** `IoRepoFolderScanner` against a temp dir — subdir with
  a `.git` directory and one with a `.git` file are returned (sorted); a plain subdir
  and loose files are excluded; a non-existent parent returns `[]`.
- **UI:** behaviour is a thin pick→scan→open loop over already-tested pieces; verified
  by the scanner test plus local run. (A full `RepoSelector` widget test would need the
  workspace/registry/drift graph; not worth the setup for a menu item — noted, not
  silently skipped.)
- Existing `flutter analyze` / `flutter test` stay green.

## Notes / non-goals

- Depth-1 only; recursive discovery is a possible future option.
- No cap on the number of repos opened (the commit graph loads lazily); if this proves
  heavy on huge folders, a confirmation could be added later.
