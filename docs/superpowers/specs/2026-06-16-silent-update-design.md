# Silent In-App Update & Auto-Relaunch — Design

**Date:** 2026-06-16
**Status:** approved
**Owner:** zN3utr4l

## Context

The in-app updater (Settings → Updates → "Download & install") downloads the
release installer, launches it, and then tells the user *"Installer launched — quit
GitOpen to finish updating."* On Windows that opens the **Inno Setup wizard** and the
user must manually quit GitOpen and click through the wizard. On Linux it
`xdg-open`s the `.deb` (system package GUI).

Current code:

- `lib/infrastructure/updates/github_release_updater.dart` — `downloadAndInstall`
  downloads then `_launch`: Windows `Process.start(file.path, [], detached)` (no args
  → wizard); Linux `xdg-open <deb>`. The app is never asked to quit.
- `lib/ui/settings/sections/updates_section.dart` — drives the flow, shows progress,
  sets the "quit to finish" message.
- `installer/windows/gitopen.iss` — `[Run]` relaunches `gitopen.exe` with flags
  `nowait postinstall skipifsilent` (so it does **not** relaunch on a silent install).

## Goal

One action updates GitOpen end to end with no wizard: download → the app closes
itself → the new version installs → the app reopens on the new version. Covers
**Windows and Linux** (owner decision 2026-06-16).

## Approach

### Windows — Inno silent install + installer-driven relaunch

1. Launch the installer with `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART` instead of no
   args.
2. Installer (`gitopen.iss`): make `[Run]` relaunch on silent installs by dropping
   `skipifsilent` (keep `nowait postinstall`), and set `AppMutex` to the
   single-instance mutex the app already creates
   (`GitOpen-SingleInstance-{A2D8F37C-2D31-4F3D-99A1-7D8B6C7E2A11}`) so Inno waits for
   the running app to close before copying files.
3. The app spawns the installer **detached** and then **quits itself** so files
   unlock. The installer (silent) installs and its `[Run]` step relaunches
   `gitopen.exe`. The single-instance mutex (added in v1.0.1) prevents any overlap:
   the old instance is gone before the new one starts.

### Linux — `pkexec dpkg -i` + app-driven relaunch

1. Install the downloaded `.deb` with `pkexec dpkg -i <deb>` and **await** it (a
   polkit password prompt appears — not fully silent, but no wizard).
2. On success, spawn the freshly installed binary detached
   (`Platform.resolvedExecutable`, which after `dpkg` points at the new
   `/opt/gitopen/gitopen`) and then quit the app. Replacing a running binary's file
   on Linux is safe (the running process keeps the old inode until it exits).
3. If `pkexec` is missing or the user cancels / `dpkg` fails (non-zero exit), fall
   back to the current behaviour (`xdg-open <deb>`) and leave the app running with an
   explanatory message.

### Shared UX

Because the app closes itself, gate the action behind a confirmation dialog:
"GitOpen will close and reopen once the update is installed. Continue?" Only on
confirm does the download+install+quit run. Download progress is shown as today.

## Components

- **`github_release_updater.dart`**
  - New pure helper `installerLaunchArgs(InstallerPlatform)` → `['/VERYSILENT',
    '/SUPPRESSMSGBOXES', '/NORESTART']` on Windows, `const []` elsewhere
    (unit-testable without `dart:io`).
  - `downloadAndInstall` (or a renamed `downloadAndInstallSilently`) branches by
    platform: Windows spawns the installer detached with the silent args (relaunch by
    installer); Linux awaits `pkexec dpkg -i`, then spawns `Platform.resolvedExecutable`
    detached. Returns normally on success; throws on a download/install failure so the
    UI can show it and keep the app open.
- **`updates_section.dart`** — add the confirm dialog before invoking the updater;
  after a successful return, close the app (via the existing window/quit path).
- **`installer/windows/gitopen.iss`** — `[Run]` flag change + `AppMutex`.

Each unit keeps one responsibility: the updater shells out and reports outcome; the
UI owns the confirmation + quit; the installer owns relaunch on Windows.

## Error handling

- Download failure → throw → UI shows "Download failed", app stays open, "Release
  page" fallback remains.
- Windows installer fails to start → throw → same handling.
- Linux `pkexec` cancelled / `dpkg` non-zero / `pkexec` absent → fall back to
  `xdg-open` and a message; app stays open.
- The app only quits **after** the installer/`dpkg` step has been kicked off
  successfully, never on an error.

## Release

Touches `lib/**` and `installer/**` → triggers `version-check` and CD. Bump
`pubspec.yaml` `1.0.1+32` → `1.0.2+33`; CD publishes **v1.0.2**.

## Testing

- **Unit:** `installerLaunchArgs` returns the silent flags on Windows and `[]`
  elsewhere. Keep the existing `selectInstallerAsset` / `_isNewer` tests green.
- **Widget:** the confirm dialog appears and only on confirm does the update run
  (inject a fake updater); cancel does nothing.
- **Manual (local, Windows now buildable):** build the installer, run
  `GitOpen-Setup-1.0.2.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART` and confirm it
  installs without a wizard and relaunches the app. Full in-app cycle verified by
  updating from an older installed build.
- **Linux:** can't be built on this Windows dev machine; CD `build-linux` is the
  compile gate. The `pkexec`/relaunch path is verified manually on a Linux box when
  available; logic kept minimal and behind the success/fallback branches.

## Risks / notes

- `AppMutex` is session-local (matches the app's mutex); the installer runs in the
  same user session at `PrivilegesRequired=lowest`, so it sees it. The app's
  self-quit is the primary unlock mechanism; `AppMutex` is the safety net.
- `pkexec` shows a password prompt — acceptable per owner decision; it is the
  no-wizard path on Linux, not a fully unattended one.
- A failed silent install leaves the user on the current version (safe); they can
  retry or use the release page.
