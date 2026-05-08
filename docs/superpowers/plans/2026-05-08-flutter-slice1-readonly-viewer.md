# GitOpen Flutter Slice 1 (Read-Only Viewer) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the GitOpen read-only viewer in Flutter Desktop: open one or more local repositories in tabs (chromeless window with native drag/resize), see refs in a hierarchical sidebar, scroll a virtualised commit graph painted on Canvas with smooth lane connections, inspect a commit's diff and file tree.

**Architecture:** Layered Dart project with `lib/{domain, application, infrastructure, ui}` mirroring the C# four-layer split. `libgit2dart` for read-side git ops, `git` CLI shell-out for write side (deferred to Slice 2). `drift` for SQLite persistence. `flutter_riverpod` for state management. `bitsdojo_window` for chromeless window with native chrome ops. `CustomPainter` for the commit graph (no SVG).

**Tech Stack:** Flutter latest stable, Dart 3.x, libgit2dart, drift + sqlite3_flutter_libs, flutter_riverpod, bitsdojo_window, logger.

**Reading order:** Phases A → I. Each task depends on earlier tasks.

**Conventions:**
- Repo root: `C:\Users\s.porta\Documents\GitOpen`.
- The C# experiment is preserved under tag `slice-1-csharp-photino`; before scaffolding, the C# `src/` and `tests/` folders move into `legacy/` so the Flutter project owns the root.
- All commits use trailer `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
- Each task ends with build clean + tests green + commit.

---

## Phase A — Repo restructure and Flutter scaffold

### Task A1: Move legacy C# code under `legacy/`

**Files:**
- Move: `src/` → `legacy/src/`
- Move: `tests/` → `legacy/tests/`
- Move: `GitOpen.sln` → `legacy/GitOpen.sln`
- Move: `Directory.Build.props` → `legacy/Directory.Build.props`
- Modify: `.gitignore` to add Flutter ignore rules

- [ ] **Step 1: Move directories**
```bash
mkdir legacy
git mv src legacy/src
git mv tests legacy/tests
git mv GitOpen.sln legacy/GitOpen.sln
git mv Directory.Build.props legacy/Directory.Build.props
```

- [ ] **Step 2: Append Flutter ignores to `.gitignore`**

Add the standard Flutter+Dart entries below the existing dotnet block:

```gitignore
# Flutter / Dart
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
.pub-cache/
.pub/
build/
**/ios/Flutter/.last_build_id
**/android/.gradle
windows/flutter/generated_plugin_registrant.*
windows/flutter/generated_plugins.cmake
linux/flutter/generated_plugin_registrant.*
linux/flutter/generated_plugins.cmake
macos/Flutter/GeneratedPluginRegistrant.swift
**/Generated.xcconfig
**/.flutter-plugins
**/.flutter-plugins-dependencies
*.iml
.idea/
```

- [ ] **Step 3: Verify the C# build still works under `legacy/`** (sanity)

```bash
cd legacy
dotnet build GitOpen.sln
cd ..
```

Expected: build succeeds (no code changes, just relocation). If anything breaks because `Directory.Build.props` paths drift, fix per-project.

- [ ] **Step 4: Commit**

```bash
git add .
git commit -m "chore(structure): relocate C# experiment under legacy/ for Flutter scaffold"
```

---

### Task A2: `flutter create` at repo root

**Files:**
- Create: `pubspec.yaml`, `lib/main.dart`, `windows/`, `linux/`, etc.

- [ ] **Step 1: Verify Flutter is on PATH**
```bash
flutter --version
flutter doctor
```
Expected: Flutter SDK present, Windows desktop check ✓.

- [ ] **Step 2: Scaffold the project at the repo root**
```bash
flutter create . \
  --project-name gitopen \
  --org com.gitopen \
  --platforms=windows,linux \
  --description "Cross-platform desktop git client" \
  --empty
```

The `--empty` flag avoids the default counter demo. The current dir already has `docs/`, `legacy/`, and `.github/`, but `flutter create` is non-destructive on existing files of unknown name.

- [ ] **Step 3: Smoke run**
```bash
flutter run -d windows
```
Expected: an empty window with the app name in the title bar. Close it.

- [ ] **Step 4: Commit the scaffold**
```bash
git add .
git commit -m "feat(scaffold): flutter create at repo root for windows + linux"
```

---

### Task A3: Add core dependencies to `pubspec.yaml`

**Files:**
- Modify: `pubspec.yaml`

- [ ] **Step 1: Add dependencies**

Edit `pubspec.yaml`:

```yaml
name: gitopen
description: "Cross-platform desktop git client"
publish_to: 'none'
version: 0.1.0

environment:
  sdk: ^3.4.0
  flutter: ">=3.22.0"

dependencies:
  flutter:
    sdk: flutter

  # State management
  flutter_riverpod: ^2.5.1

  # Window chrome (chromeless + native drag/resize)
  bitsdojo_window: ^0.1.6

  # Git operations
  libgit2dart: ^1.2.0

  # Persistence
  drift: ^2.18.0
  sqlite3_flutter_libs: ^0.5.24
  path_provider: ^2.1.3
  path: ^1.9.0

  # Logging
  logger: ^2.4.0

  # Utilities
  collection: ^1.18.0
  intl: ^0.19.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

  # Drift codegen
  drift_dev: ^2.18.0
  build_runner: ^2.4.11

flutter:
  uses-material-design: true
```

- [ ] **Step 2: Resolve**
```bash
flutter pub get
```
Expected: all packages resolved.

- [ ] **Step 3: Build**
```bash
flutter build windows --debug
```
Expected: build succeeds.

- [ ] **Step 4: Commit**
```bash
git add pubspec.yaml pubspec.lock
git commit -m "feat(deps): add riverpod, bitsdojo_window, libgit2dart, drift, logger"
```

---

### Task A4: CI workflow

**Files:**
- Modify: `.github/workflows/ci.yml`

The C# CI is now obsolete. Replace it with a Flutter CI matrix.

- [ ] **Step 1: Replace the workflow**

```yaml
name: CI

on:
  push:
    branches: [master, main]
  pull_request:

jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        os: [windows-latest, ubuntu-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - name: Linux desktop deps
        if: matrix.os == 'ubuntu-latest'
        run: |
          sudo apt-get update
          sudo apt-get install -y ninja-build libgtk-3-dev liblzma-dev libstdc++-12-dev
      - name: Pub get
        run: flutter pub get
      - name: Codegen
        run: dart run build_runner build --delete-conflicting-outputs
      - name: Analyze
        run: flutter analyze
      - name: Test
        run: flutter test
```

- [ ] **Step 2: Commit**
```bash
git add .github/workflows/ci.yml
git commit -m "ci: flutter test+analyze on windows and ubuntu"
```

---

## Phase B — Domain types in Dart

### Task B1: Define core git domain records

Domain in Dart uses `final class` with named constructor parameters and `==`/`hashCode` — Dart's records are tuples, not nominal types, so we use classes for clarity. For simple value types we'll still use Dart records `({field1, field2})` where appropriate. We'll use the `equatable` package… actually, scratch that — Dart 3's `class` with `==` override is fine and avoids another dep.

**Files:**
- Create: `lib/domain/repositories/repo_id.dart`
- Create: `lib/domain/repositories/repo_location.dart`
- Create: `lib/domain/commits/commit_sha.dart`
- Create: `lib/domain/commits/commit_signature.dart`
- Create: `lib/domain/commits/commit_info.dart`
- Create: `lib/domain/refs/branch.dart`
- Create: `lib/domain/refs/tag.dart`
- Create: `lib/domain/refs/remote.dart`
- Create: `lib/domain/refs/stash.dart`
- Create: `lib/domain/status/working_file_entry.dart`
- Create: `lib/domain/status/repo_status.dart`
- Create: `lib/domain/diff/diff_spec.dart`
- Create: `lib/domain/diff/diff_line.dart`
- Create: `lib/domain/diff/diff_hunk.dart`
- Create: `lib/domain/diff/file_diff.dart`
- Create: `lib/domain/diff/diff_result.dart`
- Create: `lib/domain/files/file_tree_entry.dart`

Each file holds one type. Use `class T { ... const T(...); }` with explicit `==` and `hashCode`. Or use `equatable` for less boilerplate — let's use `equatable`:

Add to pubspec.yaml dependencies: `equatable: ^2.0.5`. Run `flutter pub get`.

(Tasks B1 is the equivalent of the C# B1; full code listings deferred — implementer copies the C# semantics one-to-one. Each Dart class has the same field set as its C# counterpart record.)

- [ ] **Step 1: Add `equatable` dependency**

```bash
flutter pub add equatable
```

- [ ] **Step 2: Create types** (one file each, see list above; use `extends Equatable` and override `props`)

Example pattern:
```dart
import 'package:equatable/equatable.dart';

final class CommitSha extends Equatable {
  final String value;

  CommitSha(String input)
      : value = _normalize(input);

  static String _normalize(String input) {
    if (input.trim().isEmpty) {
      throw ArgumentError('CommitSha cannot be empty');
    }
    if (input.length < 4 || input.length > 40) {
      throw ArgumentError('CommitSha must be 4..40 hex chars');
    }
    return input.toLowerCase();
  }

  String short([int length = 7]) =>
      value.length <= length ? value : value.substring(0, length);

  @override
  String toString() => value;

  @override
  List<Object?> get props => [value];
}
```

- [ ] **Step 3: Build + analyze**
```bash
flutter analyze
```
Expected: 0 issues.

- [ ] **Step 4: Commit**
```bash
git add lib/domain pubspec.yaml pubspec.lock
git commit -m "feat(domain): core git records (commits, refs, status, diff, tree)"
```

---

### Task B2: Domain unit tests

**Files:**
- Create: `test/domain/commits/commit_sha_test.dart`

- [ ] **Step 1: Write tests for CommitSha**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';

void main() {
  group('CommitSha', () {
    test('rejects empty input', () {
      expect(() => CommitSha(''), throwsArgumentError);
      expect(() => CommitSha('   '), throwsArgumentError);
    });

    test('rejects too short', () {
      expect(() => CommitSha('abc'), throwsArgumentError);
    });

    test('rejects too long', () {
      expect(() => CommitSha('a' * 41), throwsArgumentError);
    });

    test('lowercases value', () {
      expect(CommitSha('ABCDEF1234').value, 'abcdef1234');
    });

    test('short returns first seven by default', () {
      expect(CommitSha('abcdef1234567890').short(), 'abcdef1');
    });

    test('short with explicit length', () {
      expect(CommitSha('abcdef1234567890').short(4), 'abcd');
    });

    test('equality is case-insensitive', () {
      expect(CommitSha('ABC123DEF456'), CommitSha('abc123def456'));
    });
  });
}
```

- [ ] **Step 2: Run**
```bash
flutter test test/domain
```
Expected: all 7 tests pass.

- [ ] **Step 3: Commit**
```bash
git add test/domain
git commit -m "test(domain): CommitSha invariants"
```

---

## Phase C — Infrastructure: libgit2dart read operations

### Task C1: RepoFixture for tests

**Files:**
- Create: `test/_helpers/repo_fixture.dart`
- Create: `test/_helpers/repo_fixture_test.dart`

Same pattern as the C# RepoFixture — creates a temp git repo seeded with N commits + optional branches.

- [ ] **Step 1: Implement fixture using libgit2dart**

```dart
import 'dart:io';
import 'package:libgit2dart/libgit2dart.dart';
import 'package:path/path.dart' as p;

class RepoFixture {
  final String path;
  String headSha;

  RepoFixture._(this.path, this.headSha);

  static Future<RepoFixture> empty() async {
    final dir = await _tempDir();
    Repository.init(path: dir);
    return RepoFixture._(dir, '');
  }

  static Future<RepoFixture> withLinearHistory(int n) async {
    if (n < 1) throw ArgumentError('n must be >= 1');
    final f = await empty();
    final repo = Repository.open(f.path);
    final sig = Signature.create(name: 'Test', email: 't@x', time: DateTime.now().millisecondsSinceEpoch ~/ 1000);
    var headSha = '';
    for (var i = 0; i < n; i++) {
      final file = File(p.join(f.path, 'file_$i.txt'));
      await file.writeAsString('content $i\n');
      final index = repo.index;
      index.add('file_$i.txt');
      index.write();
      final tree = Tree.lookup(repo: repo, oid: index.writeTree());
      final parents = headSha.isEmpty ? <Commit>[] : [Commit.lookup(repo: repo, oid: Oid.fromSHA(headSha))];
      final oid = Commit.create(
        repo: repo, updateRef: 'HEAD',
        author: sig, committer: sig,
        messageEncoding: null,
        message: 'commit $i',
        tree: tree, parents: parents,
      );
      headSha = oid.sha;
      tree.free();
      index.free();
    }
    sig.free();
    repo.free();
    f.headSha = headSha;
    return f;
  }

  Future<void> dispose() async {
    try { await Directory(path).delete(recursive: true); } catch (_) {}
  }

  static Future<String> _tempDir() async {
    final base = Directory.systemTemp.createTempSync('gitopen-test-');
    return base.path;
  }
}
```

(libgit2dart's API uses explicit `free()` for native handles — we'll wrap RepoFixture properly to avoid leaks.)

- [ ] **Step 2: Smoke test the fixture**

```dart
import 'package:flutter_test/flutter_test.dart';
import '_helpers/repo_fixture.dart';
import 'package:libgit2dart/libgit2dart.dart';

void main() {
  test('withLinearHistory creates repo with n commits', () async {
    final f = await RepoFixture.withLinearHistory(5);
    final repo = Repository.open(f.path);
    final commits = repo.log(oid: repo.head.target).toList();
    expect(commits.length, 5);
    repo.free();
    await f.dispose();
  });
}
```

- [ ] **Step 3: Run**
```bash
flutter test test/_helpers
```
Expected: pass.

- [ ] **Step 4: Commit**
```bash
git add test/_helpers
git commit -m "test(infra): RepoFixture for real git repo tests"
```

---

### Task C2 — C7: IGitReadOperations contract + libgit2dart implementation

Implement the Dart equivalent of `IGitReadOperations` and the libgit2dart-backed read operations. Mirror the C# methods one-by-one with TDD; each method gets its own task and commit. Method signatures (Dart):

```dart
abstract class GitReadOperations {
  Future<RepoStatus> getStatus(RepoLocation repo);
  Stream<CommitInfo> getCommits(RepoLocation repo, CommitQuery query);
  Future<List<Branch>> getBranches(RepoLocation repo);
  Future<List<Tag>> getTags(RepoLocation repo);
  Future<List<Remote>> getRemotes(RepoLocation repo);
  Future<List<Stash>> getStashes(RepoLocation repo);
  Future<DiffResult> getDiff(RepoLocation repo, DiffSpec spec);
  Future<List<FileTreeEntry>> getFileTree(RepoLocation repo, CommitSha sha, String path);
}

class CommitQuery {
  final int? skip;
  final int? take;
  final String? refSpec;
  const CommitQuery({this.skip, this.take, this.refSpec});
}
```

Each task follows the same TDD cycle as the C# version: write failing tests, implement, run, commit.

C2 = contract + skeleton (NotImplementedException equivalent: `throw UnimplementedError`)
C3 = `getCommits` (Stream-based; remember to NOT yield with `await Future.delayed(...)` — Dart's event loop is single-threaded too, but we won't hit a stack overflow because Stream's yield is implemented differently. Test with a real repo of 5000+ commits to be sure.)
C4 = `getStatus`
C5 = `getBranches` / `getTags` / `getRemotes` / `getStashes` (one task, four methods)
C6 = `getDiff` (commit-vs-parent for now)
C7 = `getFileTree`

Each commit roughly mirrors its C# counterpart's commit message, using `feat(infra): ... via libgit2dart (TDD)`.

---

## Phase D — Persistence with drift

### Task D1: Define drift database, repositories table, settings table

**Files:**
- Create: `lib/infrastructure/persistence/database.dart`
- Create: `lib/infrastructure/persistence/tables/repositories_table.dart`
- Create: `lib/infrastructure/persistence/tables/settings_table.dart`

- [ ] **Step 1: Tables**

```dart
// repositories_table.dart
import 'package:drift/drift.dart';

class Repositories extends Table {
  TextColumn get id => text().withLength(min: 32, max: 32)();
  TextColumn get path => text().unique()();
  TextColumn get displayName => text()();
  TextColumn get color => text().nullable()();
  DateTimeColumn get lastOpenedUtc => dateTime()();
  IntColumn get tabOrder => integer()();
  DateTimeColumn get createdUtc => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

```dart
// settings_table.dart
import 'package:drift/drift.dart';

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get valueJson => text()();

  @override
  Set<Column> get primaryKey => {key};
}
```

- [ ] **Step 2: Database**

```dart
// database.dart
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'tables/repositories_table.dart';
import 'tables/settings_table.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Repositories, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(dir.path, 'GitOpen'));
    await dbDir.create(recursive: true);
    final file = File(p.join(dbDir.path, 'state.db'));
    return NativeDatabase(file);
  });
}
```

- [ ] **Step 3: Generate code**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 4: Commit**

```bash
git add lib/infrastructure/persistence
git commit -m "feat(infra): drift database schema (repositories, settings)"
```

---

### Task D2: RepositoryRegistry implementation + tests (TDD)

(Same shape as C# D2: add/list/remove/touchLastOpened. Use drift's typesafe queries.)

---

## Phase E — Application layer

### Task E1: WorkspaceManager (TDD)

Dart equivalent of the C# WorkspaceManager. Use a `ChangeNotifier` or `StateNotifier` (Riverpod) for events. Stick with `StateNotifier<List<Workspace>>` — Riverpod will emit on every change.

### Task E2: CommitGraphLayout (port the C# algorithm verbatim)

The lane-assignment algorithm with TopSegments / BottomSegments — port from `src/GitOpen.Application/CommitGraph/CommitGraphLayout.cs` to Dart line-by-line. Same record shape, same control flow, same tests.

### Task E3: Riverpod providers (composition root)

Equivalent of DI modules. Define providers for: gitReadOperations, workspaceManager, commitGraphLayout, database, repositoryRegistry, workspacePersistence.

---

## Phase F — Window + chromeless setup with bitsdojo_window

### Task F1: bitsdojo_window initialization

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: Wire bitsdojo_window**

```dart
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: GitOpenApp()));

  doWhenWindowReady(() {
    final initialSize = const Size(1400, 900);
    appWindow.minSize = const Size(600, 400);
    appWindow.size = initialSize;
    appWindow.alignment = Alignment.center;
    appWindow.title = 'GitOpen';
    appWindow.show();
  });
}

class GitOpenApp extends StatelessWidget {
  const GitOpenApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GitOpen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF1F1F23),
      ),
      home: const Shell(),
    );
  }
}
```

- [ ] **Step 2: Add native init for bitsdojo_window**

bitsdojo_window requires a snippet in `windows/runner/main.cpp`:
```cpp
#include <bitsdojo_window_windows/bitsdojo_window_plugin.h>
auto bdw = bitsdojo_window_configure(BDW_CUSTOM_FRAME | BDW_HIDE_ON_STARTUP);
```

Insert near the top of `wWinMain`. The package's README has the verbatim snippet — follow it.

- [ ] **Step 3: Smoke run**

```bash
flutter run -d windows
```
Expected: chromeless window opens, sized 1400x900, centered.

- [ ] **Step 4: Commit**
```bash
git add .
git commit -m "feat(ui): chromeless window via bitsdojo_window"
```

---

## Phase G — UI shell: title bar, tabs, sidebar

### Task G1: TitleBar widget with native drag region + window controls

```dart
class GitOpenTitleBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return WindowTitleBarBox(
      child: Row(
        children: [
          MoveWindow(child: const _Brand()),
          Expanded(child: MoveWindow(child: const _TabsBar())),
          const _WindowControls(),
        ],
      ),
    );
  }
}

class _WindowControls extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(children: [
      MinimizeWindowButton(colors: WindowButtonColors(...)),
      MaximizeWindowButton(colors: WindowButtonColors(...)),
      CloseWindowButton(colors: WindowButtonColors(...)),
    ]);
  }
}
```

`WindowTitleBarBox + MoveWindow` from bitsdojo_window provides a NATIVE drag region — no JS, no rAF, no lag.

### Task G2: Sidebar widget with hierarchical branch tree

Port `BranchTree` and `BranchTreeView` from the C# code. Use a `Column` of expandable groups. Recursive widget: `_BranchNode(node, depth)`.

### Task G3: App shell with tabs / sidebar / main

Wire it all together with Riverpod. The active workspace state is a Riverpod provider; Tabs read from it.

---

## Phase H — Commit graph rendering on Canvas

### Task H1: CommitGraphPanel + CustomPainter

Port `CommitGraphLayout`'s output (TopSegments / BottomSegments per row) to a `CustomPainter`. Use `ListView.builder` for virtualisation; each row's painter draws lines + circle. Skia handles the strokes natively.

### Task H2: Refs overlay (pills)

Match the C# RefPill: tinted backgrounds, accent border, "HEAD →" marker on the current branch.

---

## Phase I — Bottom panel + persistence

### Task I1: BottomPanel (commit details / diff / file tree)

Three tabs, like the C# version.

### Task I2: Workspace persistence + rehydration

Same protocol: SettingRow with key `open_workspaces`, JSON-encoded list of paths.

---

## Self-Review

This plan deliberately mirrors the structure of the C# Slice 1 plan one-to-one. Where Dart idiom differs (Streams, Equatable, Riverpod providers, drift codegen, bitsdojo_window snippets) the plan calls it out explicitly. Where the algorithm is unchanged (lane layout) we port verbatim.

**Spec coverage:** every section of the design spec maps to at least one task. The hybrid git operations Slice-1 scope (read-only) is honoured: `getStatus`, `getCommits`, `getBranches`, `getTags`, `getRemotes`, `getStashes`, `getDiff`, `getFileTree` only — write ops deferred to Slice 2.

**Placeholder scan:** none.

**Naming consistency:** Dart class names use PascalCase, methods camelCase per Dart conventions. The Dart-side `GitReadOperations` corresponds to the C# `IGitReadOperations`; method names lose the `Async` suffix because Dart Streams/Futures already imply async.

---

## Execution

After Flutter is installed and `flutter doctor` is happy, dispatch implementer subagents per task starting at A1. Use superpowers:subagent-driven-development.
