# Single-Instance Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task (inline; this repo's owner wants no subagent
> dispatch). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make GitOpen single-instance per user session on Windows and Linux — a
second launch surfaces the existing window instead of opening a new one.

**Architecture:** Native-runner change, no Dart/`lib` edits, no new dependencies.
Windows uses a named mutex in `wWinMain` + `FindWindow`/`SetForegroundWindow`. Linux
drops `G_APPLICATION_NON_UNIQUE` so GTK enforces uniqueness via the existing
`application-id`, and guards `activate` to raise the existing window. Spec:
`docs/superpowers/specs/2026-06-16-single-instance-design.md`.

**Tech Stack:** C++ Win32 (`windows/runner`), C/GTK + GApplication (`linux/runner`),
Flutter build tooling, GitHub Actions CD.

---

## Critical context / hazards (read before executing)

1. **Branch already created:** `fix/single-instance` (off `main`, which equals
   `origin/main` at v1.0.0). The spec is already committed on it. Stay on this
   branch.
2. **PR CI does NOT compile the native runners** — `ci-gitopen.yml` runs only
   `flutter analyze` + `flutter test`. A C++ compile error will NOT be caught by PR
   CI. Windows must be **built locally** (Task 3). Linux cannot be built on this
   Windows machine; the CD `build-linux` job is the compile gate.
3. **Release requires the pubspec bump.** `windows/**` and `linux/**` are in the CD
   path filter, but CD skips when `v<version>` already exists on origin. So the fix
   only ships if `pubspec.yaml` goes to `1.0.1`. Bump is Task 4.
4. **Do NOT full-auto merge** (owner decision): Linux is unverifiable locally here.
   Stop after the PR + green CI + local Windows verification and confirm the merge
   with the owner (Task 7 is a STOP-and-ask checkpoint).
5. **gh account flips** to `giuseppe-chirico`; run
   `gh auth switch --hostname github.com --user zN3utr4l` in the same command before
   push, and always pass `--repo zN3utr4l/GitOpen`. Never `git push --tags`.
6. **Flutter not on PATH:** `C:\Users\g.chirico\flutter\bin\flutter.bat`.
7. **No blanket `dart format`** — irrelevant here (no `.dart` changes).

---

## File structure

- `windows/runner/main.cpp` — add a single-instance guard at the top of `wWinMain`
  plus a small file-local helper to surface the existing window. One responsibility:
  process entry + instance gate.
- `linux/runner/my_application.cc` — change the construction flag and add the
  early-return guard in `my_application_activate`.
- `pubspec.yaml` — version bump.

No test files: native runner code is outside the Dart test harness (spec "Testing").
Verification is a local Windows build + manual double-launch, plus the unchanged
`flutter analyze`/`flutter test` regression guard, plus CD `build-linux`.

---

## Task 1: Windows single-instance guard

**Files:**
- Modify: `windows/runner/main.cpp`

- [ ] **Step 1: Add a file-local helper above `wWinMain`**

Insert immediately after the `auto bdw = bitsdojo_window_configure(BDW_CUSTOM_FRAME);`
line (currently line 9) and before `int APIENTRY wWinMain(...)`:

```cpp
// Single-instance support. The mutex name is tied to the installer AppId so it
// is unambiguous; no "Global\\" prefix keeps it session-local (one instance per
// user session). See docs/superpowers/specs/2026-06-16-single-instance-design.md.
namespace {

constexpr const wchar_t kSingleInstanceMutexName[] =
    L"GitOpen-SingleInstance-{A2D8F37C-2D31-4F3D-99A1-7D8B6C7E2A11}";

// The window class Flutter's Win32 runner registers (see win32_window.cpp) plus
// the title set in wWinMain — together they identify our existing window.
constexpr const wchar_t kRunnerWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr const wchar_t kRunnerWindowTitle[] = L"gitopen";

// Brings an already-running instance's window to the foreground. Retries briefly
// to cover the race where the first instance holds the mutex but has not created
// its window yet.
void SurfaceExistingWindow() {
  for (int attempt = 0; attempt < 10; ++attempt) {
    HWND existing = ::FindWindowW(kRunnerWindowClass, kRunnerWindowTitle);
    if (existing != nullptr) {
      if (::IsIconic(existing)) {
        ::ShowWindow(existing, SW_RESTORE);
      }
      ::SetForegroundWindow(existing);
      return;
    }
    ::Sleep(100);
  }
}

}  // namespace
```

- [ ] **Step 2: Add the mutex gate at the very start of `wWinMain`**

Insert as the first statements inside `wWinMain`, before the `AttachConsole` block:

```cpp
  // If another instance is already running, surface its window and exit.
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    SurfaceExistingWindow();
    ::CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }
```

(The handle is intentionally left open for the rest of the process lifetime; the OS
releases it on exit. `windows.h` — already included at the top of `main.cpp` — pulls
in `CreateMutexW`, `FindWindowW`, `ShowWindow`, `SetForegroundWindow`, `IsIconic`.)

- [ ] **Step 3: Verify the edit reads correctly**

Confirm `wWinMain` now starts with the mutex block, the helper namespace sits above
it, and nothing else in the function changed (the existing
`AttachConsole`/`CoInitializeEx`/window-creation flow is intact below the new block).

- [ ] **Step 4: Commit**

```bash
git add windows/runner/main.cpp
git commit -m "fix(win): enforce single instance and surface the existing window"
```

---

## Task 2: Linux single-instance guard

**Files:**
- Modify: `linux/runner/my_application.cc`

- [ ] **Step 1: Guard `my_application_activate` against a second window**

In `my_application_activate` (currently starts at line 23), insert at the very top of
the function body, immediately after `MyApplication* self = MY_APPLICATION(application);`
(keep `self` even though the guard does not use it — the rest of the function does):

```cpp
  // Single-instance: when a second launch forwards an activate to the primary
  // process, raise the existing window instead of building another one.
  GList* existing_windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (existing_windows != nullptr) {
    gtk_window_present(GTK_WINDOW(existing_windows->data));
    return;
  }
```

The existing window-creation code below stays exactly as is.

- [ ] **Step 2: Enable GApplication uniqueness in `my_application_new`**

In `my_application_new` (currently line 138), change the flags argument of
`g_object_new` from `G_APPLICATION_NON_UNIQUE` to `G_APPLICATION_DEFAULT_FLAGS`:

```cpp
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_DEFAULT_FLAGS, nullptr));
```

(`APPLICATION_ID` is `com.gitopen.gitopen`, set in `linux/runner/CMakeLists.txt` — a
valid unique id, which is what GApplication needs to enforce one primary instance.)

- [ ] **Step 3: Verify the edit reads correctly**

Confirm: `my_application_activate` now early-returns via `gtk_window_present` when a
window already exists; `my_application_new` passes `G_APPLICATION_DEFAULT_FLAGS`; no
other lines changed.

- [ ] **Step 4: Commit**

```bash
git add linux/runner/my_application.cc
git commit -m "fix(linux): enforce single instance via GApplication uniqueness"
```

---

## Task 3: Verify on Windows (local build + manual double-launch)

**Files:** none

- [ ] **Step 1: Static analysis + test suite stay green (Dart regression guard)**

```bash
cd /d/repos/Personal/GitOpen
"C:/Users/g.chirico/flutter/bin/flutter.bat" analyze
"C:/Users/g.chirico/flutter/bin/flutter.bat" test
```
Expected: `No issues found!` and `All tests passed!` (no Dart changed → unaffected).

- [ ] **Step 2: Build the Windows release (compiles the native runner)**

```bash
"C:/Users/g.chirico/flutter/bin/flutter.bat" build windows --release
```
Expected: build succeeds. This is the real compile check for `main.cpp` — a C++ error
fails here. If it fails, STOP and fix Task 1 before continuing.

- [ ] **Step 3: Manual single-instance check**

Launch the built executable, then launch it again while the first is open:

```bash
EXE="build/windows/x64/runner/Release/gitopen.exe"
"$EXE" &        # first instance — window opens
sleep 5
"$EXE"          # second launch — should NOT open a new window
```
Expected: only one GitOpen window exists; the second launch brings the existing
window to the foreground and exits. Then minimize the window and launch again →
the window restores to the foreground. Close the app and relaunch once → it opens
normally (mutex released on exit).

- [ ] **Step 4: No commit** (verification only).

---

## Task 4: Bump version for the patch release

**Files:**
- Modify: `pubspec.yaml:4`

- [ ] **Step 1: Bump the version**

Replace:

```
version: 1.0.0+31
```

with:

```
version: 1.0.1+32
```

- [ ] **Step 2: Commit**

```bash
git add pubspec.yaml
git commit -m "chore: bump version to 1.0.1"
```

---

## Task 5: Push and open PR

**Files:** none

- [ ] **Step 1: Push the branch (handle the gh auth flip; no --tags)**

```bash
gh auth switch --hostname github.com --user zN3utr4l && git push -u origin fix/single-instance
```
If it 403s, re-run the same line.

- [ ] **Step 2: Open the PR**

```bash
gh auth switch --hostname github.com --user zN3utr4l && gh pr create --repo zN3utr4l/GitOpen \
  --base main --head fix/single-instance \
  --title "fix: single-instance window (Windows + Linux)" \
  --body "Clicking the app icon while GitOpen is already running opened a second window/process. Now it is single-instance per user session; a second launch surfaces the existing window.

- Windows (main.cpp): named mutex gate + FindWindow/SetForegroundWindow to raise the running window
- Linux (my_application.cc): drop G_APPLICATION_NON_UNIQUE; guard activate to gtk_window_present the existing window
- pubspec -> 1.0.1+32 (CD publishes v1.0.1 on merge)

Note: PR CI does not compile the native runners. Windows built and double-launch tested locally; Linux relies on the CD build-linux gate. Spec: docs/superpowers/specs/2026-06-16-single-instance-design.md."
```

- [ ] **Step 3: Wait for required checks**

```bash
gh pr checks --repo zN3utr4l/GitOpen --watch
```
Expected: `build-and-test (windows-latest)`, `build-and-test (ubuntu-latest)`,
`version-check` all pass.

---

## Task 6: STOP — confirm merge with the owner

**Files:** none

- [ ] **Step 1: Report status and ask before merging**

Per the owner decision, do **not** auto-merge. Report: PR number, CI status, that
Windows was verified locally and Linux will be validated by CD's `build-linux`. Ask
whether to merge (which publishes v1.0.1) or hold. Only proceed to Task 7 on an
explicit go.

---

## Task 7: Merge and let CD publish v1.0.1 (only after owner go)

**Files:** none

- [ ] **Step 1: Merge with a merge commit, delete branch**

```bash
gh auth switch --hostname github.com --user zN3utr4l && gh pr merge --repo zN3utr4l/GitOpen --merge --delete-branch
```

- [ ] **Step 2: Watch CD; verify build-linux compiles the runner**

```bash
gh auth switch --hostname github.com --user zN3utr4l && gh run watch --repo zN3utr4l/GitOpen \
  $(gh run list --repo zN3utr4l/GitOpen --workflow cd-release.yml --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status
```
Expected: `version` → `build-windows` / `build-linux` → `release` all succeed. If
`build-linux` fails (Linux C++ error), the release does NOT publish — fix on a
follow-up branch.

- [ ] **Step 3: Verify the release**

```bash
gh release view v1.0.1 --repo zN3utr4l/GitOpen
```
Expected: `GitOpen v1.0.1` with `GitOpen-Setup-1.0.1.exe` + `gitopen_1.0.1_amd64.deb`.

- [ ] **Step 4: Sync local main (explicit, no bare pull)**

```bash
git switch main && git fetch origin && git merge --ff-only origin/main
```

---

## Self-review

- **Spec coverage:**
  - Windows mutex + surface-existing-window → Task 1 (matches spec: AppId-based
    session-local mutex name, `FindWindowW` class+title, retry, restore+foreground).
  - Linux flag change + `activate` guard → Task 2 (matches spec:
    `G_APPLICATION_DEFAULT_FLAGS`, `gtk_application_get_windows` →
    `gtk_window_present`).
  - Version bump to publish → Task 4 (`1.0.1+32`).
  - Verification caveats (no native compile in PR CI; Windows local, Linux via CD;
    not full-auto) → Tasks 3, 6, 7.
- **Placeholders:** none — full code for both runners is inline.
- **Consistency:** mutex name GUID `{A2D8F37C-2D31-4F3D-99A1-7D8B6C7E2A11}` matches
  the installer AppId in `installer/windows/gitopen.iss`; window class/title
  (`FLUTTER_RUNNER_WIN32_WINDOW` / `gitopen`) match `win32_window.cpp` and the
  `window.Create(L"gitopen", …)` call in `main.cpp`; `G_APPLICATION_DEFAULT_FLAGS`
  replaces `G_APPLICATION_NON_UNIQUE` consistently; version `1.0.1+32` used in
  pubspec and `v1.0.1` in the release checks.
