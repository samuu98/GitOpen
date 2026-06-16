# Single-Instance Window — Design

**Date:** 2026-06-16
**Status:** approved
**Owner:** zN3utr4l

## Context

Launching GitOpen again while it is already running (e.g. clicking the Windows
Start-menu icon repeatedly) opens a second window / process. The desired behaviour
is a single-instance application: the first launch opens the window; subsequent
launches surface the existing window instead of creating a new one.

Confirmed in the runners:

- **Windows** (`windows/runner/main.cpp`): `wWinMain` unconditionally creates a
  `FlutterWindow` every launch — no instance guard.
- **Linux** (`linux/runner/my_application.cc`): the `GtkApplication` is constructed
  with `G_APPLICATION_NON_UNIQUE` (line 147), which explicitly disables GTK's
  built-in single-instance handling (the Flutter template default). Additionally,
  `my_application_activate` builds a brand-new window every time it is invoked.

Scope decision (owner, 2026-06-16): cover **both** Windows and Linux.

## Goal

A single running instance per user session on Windows and Linux. A second launch
brings the existing window to the foreground (restoring it if minimized) and exits,
opening no new window.

## Approach (per platform, idiomatic, no new dependencies)

### Windows — named mutex in `main.cpp`

At the very start of `wWinMain`, before any window/engine init:

1. `CreateMutexW(nullptr, TRUE, <unique name>)`. The name is tied to the installer
   AppId to be unambiguous: `L"GitOpen-SingleInstance-{A2D8F37C-2D31-4F3D-99A1-7D8B6C7E2A11}"`.
   No `Global\` prefix → the mutex lives in the session namespace, giving
   single-instance **per user session** (the right granularity for a desktop app).
2. If `GetLastError() == ERROR_ALREADY_EXISTS`, another instance owns it:
   - Locate the existing top-level window with
     `FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"gitopen")` (the Flutter window
     class plus the title set in `main.cpp`). A short bounded retry (≈10 × 100 ms)
     covers the race where the first instance has the mutex but has not created its
     window yet.
   - If found: `ShowWindow(hwnd, SW_RESTORE)` (un-minimize) then
     `SetForegroundWindow(hwnd)`.
   - `CloseHandle(mutex)` and `return EXIT_SUCCESS`.
3. Otherwise proceed with the existing startup. Keep the mutex handle open for the
   process lifetime (the OS releases it on exit).

Rationale: the mutex check runs before the heavy Flutter engine starts, so the
duplicate process exits cheaply. `FindWindow` + foreground is the standard Win32
surfacing pattern. `bitsdojo_window`'s custom frame does not change the window class
or title, so the lookup is unaffected. Focus-stealing mitigation by the OS may
occasionally only flash the taskbar; acceptable and matches native app behaviour.

### Linux — GApplication uniqueness in `my_application.cc`

1. Replace `G_APPLICATION_NON_UNIQUE` with `G_APPLICATION_DEFAULT_FLAGS` in
   `my_application_new`. With the existing `application-id` (`com.gitopen.gitopen`),
   GApplication enforces uniqueness for free: the first process becomes primary;
   later launches register as remote, forward an `activate` to the primary over the
   session bus, and exit.
2. Guard `my_application_activate` so the primary does not build a second window
   when it receives the forwarded `activate`:

   ```c
   GList* windows = gtk_application_get_windows(GTK_APPLICATION(application));
   if (windows != nullptr) {
     gtk_window_present(GTK_WINDOW(windows->data));
     return;
   }
   // ... existing window-creation code unchanged ...
   ```

   `gtk_application_window_new` registers the window with the application, so
   `gtk_application_get_windows` returns it on subsequent activations.

Rationale: this is the canonical GTK single-instance pattern and reuses the IPC GTK
already provides; `gtk_window_present` raises/un-minimizes the existing window.

## Files

- Modify: `windows/runner/main.cpp` — mutex guard + surface-existing-window helper.
- Modify: `linux/runner/my_application.cc` — flag change + `activate` guard.
- Modify: `pubspec.yaml` — `1.0.0+31` → `1.0.1+32` (so CD publishes the fix).

No Dart/`lib` changes. No new dependencies.

## Release

`windows/**` and `linux/**` are in the CD path filter, so merging triggers CD. CD
skips the build when `v<version>` already exists on origin, so the version **must**
be bumped to `1.0.1` for the fix to be published as **v1.0.1**. (`version-check`
only mandates a bump when `lib/` or `pubspec.yaml` change; bumping satisfies it
regardless.)

## Testing / verification

Native runner code is not exercised by the Dart suite, and PR CI runs only
`flutter analyze` + `flutter test` — it does **not** compile the runners. Therefore:

- **Windows:** build and run locally — `flutter build windows --release`, then launch
  the built `gitopen.exe` twice and confirm the second launch surfaces the first
  window instead of opening a new one. Also confirm a normal single launch still
  opens correctly and minimized→relaunch restores.
- **Linux:** cannot be built on the Windows dev machine. The change is minimal and
  idiomatic; the CD `build-linux` job is the compile gate (a failure there blocks
  the release, so no broken artifact ships). Given this, the v1.0.1 release will
  **not** be full-auto-merged — stop after the PR + local Windows verification and
  decide the merge with the owner.
- Existing `flutter analyze` / `flutter test` must stay green (regression guard;
  expected unaffected since no Dart changes).

## Risks / notes

- `SetForegroundWindow` may be throttled by Windows' foreground lock; worst case the
  taskbar button flashes rather than raising. Acceptable.
- Startup race (mutex held, window not yet created) handled by the bounded retry on
  Windows; on Linux GApplication serializes activation, so no equivalent race.
- Multi-session edge: a session-local mutex permits one instance per user session,
  which is the intended behaviour.
