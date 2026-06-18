# Repository info panel (local path, remote URL, git identity)

**Date:** 2026-06-18
**Status:** Approved design, pending implementation plan

## Problem

There's no single place that shows, for the active repo: where it lives on
disk, its remote URL, and **which git identity** commits will use there. The
local path is buried in the repo-catalog popover, the remote URL only shows as
a sidebar tooltip, and the effective `user.name`/`user.email` isn't surfaced at
all — yet on a machine with per-folder identities (personal vs work) it's the
thing you most want to confirm before committing.

## Goal

An info button next to the active repo name in the title bar opens a small
**Repository** panel showing:
- the **local folder path** — with copy + open-in-file-manager,
- the **remote (origin) URL** — with copy + open-in-browser,
- the **git user** (effective `name <email>`) — with copy.

## Decisions (locked during brainstorming)

- Lives in a **panel opened from the repo name** (title bar info icon), not a
  Settings section.
- Shows the **origin** remote only (not every remote).
- Includes the **effective git identity** for the repo (the user's addition).
- Actions: copy (path + URL + identity), open folder, open remote in browser.
- Read-only: editing remote/identity stays in the sidebar / Settings.

## Design

### 1. Pure `remoteWebUrl` (open-in-browser normalization)

New pure function (testable), converts a git remote URL to a browsable https
URL:
```dart
// lib/application/git/remote_web_url.dart
String? remoteWebUrl(String gitUrl);
```
- `git@github.com:owner/repo.git` → `https://github.com/owner/repo`
- `ssh://git@host/owner/repo.git` → `https://host/owner/repo`
- `https://host/owner/repo.git` → `https://host/owner/repo`
- `http(s)://…` passes through (minus a trailing `.git`)
- returns null when it can't produce an `http(s)` URL (button hidden).

### 2. Data — `repoInfoProvider`

`repoInfoProvider(RepoLocation)` (FutureProvider.family) returns a small record:
```dart
({String path, String? originUrl, String? userName, String? userEmail})
```
- `path` = `repo.path` (immediate).
- `originUrl` = `remoteUrlReaderProvider.remoteUrl(repo, 'origin')` (null when
  there's no origin).
- `userName` / `userEmail` = `gitIdentityServiceProvider.readEffective(repo)`
  (local overrides global; null when unset).

It's read when the dialog opens (a quick `git config` + `git remote get-url`);
not on the hot path.

### 3. UI — info button + `RepoInfoDialog`

- In `main.dart`'s `_TitleBar`, add an `IconButton(Icons.info_outline)` right
  after the `RepoSelector`, shown only when a repo is active; tapping opens
  `RepoInfoDialog.show(context, repo: active.location)`.
- `RepoInfoDialog` (an `AppDialog` titled "Repository") watches
  `repoInfoProvider(repo)` and renders three rows; each row is a label, a
  monospace value (selectable + ellipsized), and trailing icon actions:
  - **Local path** — copy, open folder.
  - **Remote (origin)** — copy, open in browser (button hidden when no origin
    or `remoteWebUrl` is null). Shows "No remote" when origin is absent.
  - **Git user** — `name <email>`, copy. Shows "Not set" when both are null.
- A shared tiny `_InfoRow` widget keeps the three rows consistent.

### 4. Actions

- **Copy**: `Clipboard.setData(ClipboardData(text: value))` + a brief snackbar
  ("Copied").
- **Open folder**: reveal the path in the OS file manager. New
  `FolderRevealer` port + `SystemFolderRevealer` impl: Windows `explorer <path>`,
  Linux `xdg-open <path>`, macOS `open <path>`. Wired via `folderRevealerProvider`.
  (Distinct from the existing repo *launcher*, which opens repos in editors.)
- **Open in browser**: `launchUrl(Uri.parse(remoteWebUrl(originUrl)!),
  mode: externalApplication)` (url_launcher is already a dependency).

### 5. Error handling & edge cases

- No origin remote → "No remote", no copy/open-browser for it.
- `remoteWebUrl` returns null (unparseable) → open-browser hidden, copy still
  shows the raw URL.
- Identity unset (bare/global-less) → "Not set".
- `repoInfoProvider` errors (e.g. git missing) → dialog shows "—" placeholders
  rather than throwing; the dialog still opens.
- The info button only renders when a repo is active (no repo → no button).

## Testing

- `remoteWebUrl` — pure: ssh `git@`, `ssh://`, https-with-`.git`, already-http,
  unparseable → null.
- `repoInfoProvider` — fixture repo with an origin + a local identity → record
  has the path, origin URL, name/email.
- `RepoInfoDialog` widget test — overrides `repoInfoProvider` with a record;
  asserts the three values render, copy puts the right text on the clipboard,
  and the open-browser button is hidden when origin is null.

## Non-goals

- Listing every remote (origin only).
- Editing the remote URL or identity from this panel (already in sidebar /
  Settings → Git identity).
- A persistent always-visible panel (it's an on-demand dialog).
