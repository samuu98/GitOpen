# Open a Folder of Repositories — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans
> (inline; no subagent dispatch). Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add "Open folder of repos..." — pick a parent folder and open every git repo
in its immediate subdirectories as workspace tabs.

**Architecture:** A `RepoFolderScanner` port (application) + `IoRepoFolderScanner`
(infrastructure, `dart:io`) discover repos by checking each immediate subdirectory for
`.git`. The `RepoSelector` UI wires picker → scan → `workspaceManager.open` (dedups) →
select first. Spec: `docs/superpowers/specs/2026-06-16-open-repos-folder-design.md`.

**Tech Stack:** Dart/Flutter, Riverpod, drift (registry), GitHub CD.

---

## Critical context / hazards

1. **Branch `feat/open-repos-folder`** off `main` (at v1.0.2); spec committed. Stay here.
2. `DriftRepositoryRegistry.add` does **not** validate git-ness → the scanner must
   return only real repos.
3. `workspaceManager.open(path)` already dedups by `location.id`, so re-opening an
   already-open repo is a no-op returning the existing workspace.
4. **gh flips** → `gh auth switch --hostname github.com --user zN3utr4l` before
   push/merge; `--repo zN3utr4l/GitOpen`; never `--tags`.
5. **Local builds work**; `flutter analyze`/`flutter test` cover this (pure Dart, no
   native/installer change). **Publishing v1.0.3 is a public release — confirm before
   the final merge** (auto-mode blocks unconfirmed release merges).
6. Flutter: `C:\Users\g.chirico\flutter\bin\flutter.bat`. No blanket `dart format`.

---

## File structure

- Create: `lib/application/launcher/repo_folder_scanner.dart` — the port.
- Create: `lib/infrastructure/launcher/io_repo_folder_scanner.dart` — the impl.
- Create: `test/infrastructure/launcher/io_repo_folder_scanner_test.dart` — fixture test.
- Modify: `lib/application/providers.dart` — register `repoFolderScannerProvider`.
- Modify: `lib/ui/shell/repo_selector.dart` — menu item + `_openReposFolder`.
- Modify: `pubspec.yaml` — `1.0.2+33` → `1.0.3+34`.

---

## Task 1: Scanner port + impl + test (TDD)

**Files:**
- Create: `lib/application/launcher/repo_folder_scanner.dart`
- Create: `lib/infrastructure/launcher/io_repo_folder_scanner.dart`
- Create: `test/infrastructure/launcher/io_repo_folder_scanner_test.dart`

- [ ] **Step 1: Write the port**

`lib/application/launcher/repo_folder_scanner.dart`:

```dart
/// Discovers git repositories inside a parent folder so the UI can open a whole
/// folder of repos at once. Scans only immediate subdirectories (depth 1).
// ignore: one_member_abstracts
abstract interface class RepoFolderScanner {
  /// Absolute paths of git repositories that are immediate children of
  /// [parentPath], sorted by path. Empty when the parent is missing or has none.
  Future<List<String>> findRepositories(String parentPath);
}
```

- [ ] **Step 2: Write the failing test**

`test/infrastructure/launcher/io_repo_folder_scanner_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/launcher/io_repo_folder_scanner.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('gitopen_scan_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('returns immediate subdirs with a .git directory or file, sorted', () async {
    // a/.git (directory) — a normal clone.
    Directory(p.join(root.path, 'a', '.git')).createSync(recursive: true);
    // c/.git (file) — a worktree/submodule.
    Directory(p.join(root.path, 'c')).createSync();
    File(p.join(root.path, 'c', '.git')).writeAsStringSync('gitdir: ../x');
    // b — a plain folder, not a repo.
    Directory(p.join(root.path, 'b')).createSync();
    // loose.txt — a file, not a directory.
    File(p.join(root.path, 'loose.txt')).writeAsStringSync('x');

    final repos = await const IoRepoFolderScanner().findRepositories(root.path);

    expect(repos, [p.join(root.path, 'a'), p.join(root.path, 'c')]);
  });

  test('returns empty for a non-existent parent', () async {
    final missing = p.join(root.path, 'nope');
    expect(await const IoRepoFolderScanner().findRepositories(missing), isEmpty);
  });
}
```

- [ ] **Step 3: Run, expect failure**

Run: `"C:/Users/g.chirico/flutter/bin/flutter.bat" test test/infrastructure/launcher/io_repo_folder_scanner_test.dart`
Expected: FAIL — `IoRepoFolderScanner` undefined.

- [ ] **Step 4: Write the impl**

`lib/infrastructure/launcher/io_repo_folder_scanner.dart`:

```dart
import 'dart:io';

import 'package:gitopen/application/launcher/repo_folder_scanner.dart';
import 'package:path/path.dart' as p;

/// Filesystem-backed [RepoFolderScanner]: an immediate subdirectory is a repo
/// when it contains a `.git` entry (a directory for clones, a file for
/// worktrees/submodules).
final class IoRepoFolderScanner implements RepoFolderScanner {
  const IoRepoFolderScanner();

  @override
  Future<List<String>> findRepositories(String parentPath) async {
    final parent = Directory(parentPath);
    if (!parent.existsSync()) return const [];
    final repos = <String>[];
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final gitPath = p.join(entity.path, '.git');
      if (Directory(gitPath).existsSync() || File(gitPath).existsSync()) {
        repos.add(entity.path);
      }
    }
    repos.sort();
    return repos;
  }
}
```

- [ ] **Step 5: Run, expect pass**

Run: `"C:/Users/g.chirico/flutter/bin/flutter.bat" test test/infrastructure/launcher/io_repo_folder_scanner_test.dart`
Expected: PASS (both tests).

- [ ] **Step 6: Commit**

```bash
git add lib/application/launcher/repo_folder_scanner.dart lib/infrastructure/launcher/io_repo_folder_scanner.dart test/infrastructure/launcher/io_repo_folder_scanner_test.dart
git commit -m "feat(repos): scanner that finds git repos in a folder's subdirectories"
```

---

## Task 2: Register the provider

**Files:**
- Modify: `lib/application/providers.dart`

- [ ] **Step 1: Add imports**

Add (with the other `application/launcher` and `infrastructure` imports):

```dart
import 'package:gitopen/application/launcher/repo_folder_scanner.dart';
import 'package:gitopen/infrastructure/launcher/io_repo_folder_scanner.dart';
```

- [ ] **Step 2: Add the provider**

Add right after the `folderPickerProvider` definition:

```dart
/// Finds git repos directly inside a chosen folder (file-system backed).
final repoFolderScannerProvider = Provider<RepoFolderScanner>(
  (ref) => const IoRepoFolderScanner(),
);
```

- [ ] **Step 3: Analyze**

Run: `"C:/Users/g.chirico/flutter/bin/flutter.bat" analyze lib/application/providers.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/application/providers.dart
git commit -m "feat(repos): provide the repo folder scanner"
```

---

## Task 3: "Open folder of repos..." menu item

**Files:**
- Modify: `lib/ui/shell/repo_selector.dart`

- [ ] **Step 1: Add the menu item**

In the `menuChildren` list, insert this `MenuItemButton` immediately after the
"Open repository..." item (the one with `onPressed: _openRepo`) and before the
"Clone repository..." item:

```dart
        MenuItemButton(
          style: ButtonStyle(
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) return palette.bg4;
              return Colors.transparent;
            }),
          ),
          leadingIcon: Icon(Icons.folder_copy, size: 16, color: palette.fg1),
          onPressed: _openReposFolder,
          child: Text(
            'Open folder of repos...',
            style: TextStyle(color: palette.fg0, fontSize: 12.5),
          ),
        ),
```

- [ ] **Step 2: Add the handler**

Add this method to `_RepoSelectorState`, right after `_openRepo`:

```dart
  Future<void> _openReposFolder() async {
    _menu.close();
    final picker = ref.read(folderPickerProvider);
    final parent = await picker.pickFolder('Open folder of repositories');
    if (parent == null) return;
    final paths =
        await ref.read(repoFolderScannerProvider).findRepositories(parent);
    if (!mounted) return;
    if (paths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No git repositories found in $parent')),
      );
      return;
    }
    final manager = ref.read(workspaceManagerProvider.notifier);
    RepoId? firstId;
    for (final path in paths) {
      try {
        final ws = await manager.open(path);
        firstId ??= ws.location.id;
      } on Object catch (_) {
        // Skip a repo that fails to open; keep opening the rest.
      }
    }
    if (firstId != null) {
      ref.read(activeWorkspaceIdProvider.notifier).state = firstId;
    }
  }
```

(`repoFolderScannerProvider` comes from the already-imported `providers.dart`;
`RepoId`, `ScaffoldMessenger`, `workspaceManagerProvider`, `activeWorkspaceIdProvider`
are already imported in this file.)

- [ ] **Step 3: Analyze**

Run: `"C:/Users/g.chirico/flutter/bin/flutter.bat" analyze lib/ui/shell/repo_selector.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/ui/shell/repo_selector.dart
git commit -m "feat(repos): open every git repo in a chosen folder from the selector"
```

---

## Task 4: Version bump

**Files:**
- Modify: `pubspec.yaml:4`

- [ ] **Step 1: Bump** — replace `version: 1.0.2+33` with `version: 1.0.3+34`.

- [ ] **Step 2: Commit**

```bash
git add pubspec.yaml
git commit -m "chore: bump version to 1.0.3"
```

---

## Task 5: Verify locally

- [ ] **Step 1: Analyze + full suite**

```bash
cd /d/repos/Personal/GitOpen
"C:/Users/g.chirico/flutter/bin/flutter.bat" analyze
"C:/Users/g.chirico/flutter/bin/flutter.bat" test
```
Expected: `No issues found!` and `All tests passed!`.

- [ ] **Step 2: Optional sanity run** — `flutter run -d windows`, open the selector,
  "Open folder of repos..." on `D:\repos\Personal`, confirm the child repos open as
  tabs. (Skip if not running interactively; the scanner is unit-tested.)

---

## Task 6: Push + PR

- [ ] **Step 1: Push**

```bash
gh auth switch --hostname github.com --user zN3utr4l && git push -u origin feat/open-repos-folder
```

- [ ] **Step 2: Open PR**

```bash
gh auth switch --hostname github.com --user zN3utr4l && gh pr create --repo zN3utr4l/GitOpen \
  --base main --head feat/open-repos-folder \
  --title "feat: open every git repo in a folder" \
  --body "Adds 'Open folder of repos...' to the repo selector: pick a parent folder and open every git repo in its immediate subdirectories as tabs.

- RepoFolderScanner port + IoRepoFolderScanner (depth-1, detects .git dir or file), unit-tested
- RepoSelector menu item wires picker -> scan -> open (dedup) -> select first; SnackBar when none found
- pubspec -> 1.0.3+34 (CD publishes v1.0.3)

Spec: docs/superpowers/specs/2026-06-16-open-repos-folder-design.md."
```

- [ ] **Step 3: Wait for checks**

```bash
gh pr checks --repo zN3utr4l/GitOpen --watch
```
Expected: `build-and-test` (both OS) + `version-check` pass.

---

## Task 7: Confirm merge, then publish v1.0.3

- [ ] **Step 1: STOP — confirm with the owner** (merge publishes public v1.0.3).
- [ ] **Step 2: Merge**

```bash
gh auth switch --hostname github.com --user zN3utr4l && gh pr merge --repo zN3utr4l/GitOpen --merge --delete-branch
```

- [ ] **Step 3: Watch CD + verify**

```bash
gh auth switch --hostname github.com --user zN3utr4l && gh run watch --repo zN3utr4l/GitOpen \
  $(gh run list --repo zN3utr4l/GitOpen --workflow cd-release.yml --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status
gh release view v1.0.3 --repo zN3utr4l/GitOpen
```
Expected: CD green; release `GitOpen v1.0.3` with both artifacts. (No `.iss` change this
time, so the CD installer step is unaffected.)

- [ ] **Step 4: Sync local main**

```bash
git switch main && git fetch origin && git merge --ff-only origin/main
```

---

## Self-review

- **Spec coverage:** port + impl (depth-1, `.git` dir/file) → Task 1; provider → Task 2;
  menu item + pick→scan→open→select + empty SnackBar → Task 3; release → Tasks 4,7.
- **Placeholders:** none — full code inline for port, impl, test, provider, UI.
- **Consistency:** `RepoFolderScanner.findRepositories` signature matches across port,
  impl, test, and UI; `repoFolderScannerProvider` defined in Task 2 used in Task 3;
  version `1.0.3+34` / `v1.0.3` consistent.
- **Known non-test:** the `RepoSelector` menu wiring isn't widget-tested (heavy
  workspace/drift graph for a menu item); covered by the scanner unit test + optional
  local run.
```
