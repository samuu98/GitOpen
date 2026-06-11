# Phase 5 — S2 Diff & Viewer Extras Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Image diff previews for binary image files, a flat/tree toggle for the working-copy and commit file lists, and a branch "Compare with…" view (ahead/behind counts + commit lists + combined diff).

**Architecture:** Three independent features behind the existing read facade. (A) New read op `getFileBytes` (raw blob bytes via `git cat-file`, disk for the working tree) + a shared `ImageDiffView` widget rendered wherever a binary diff is an image. (B) Pure `buildFileTree` path-folding helper + a persisted `fileListsAsTree` setting + tree rendering in `FileList` (working copy) and `FileTreeViewWidget` (bottom panel). (C) New read op `countDivergence` (`rev-list --left-right --count`) + `CompareRefsDialog` fed by the existing `getCommits(refSpec)` and `getDiff(DiffSpecCommitVsCommit)`.

**Tech Stack:** Dart/Flutter, riverpod, system git CLI, real-git fixture tests (`test/_helpers/repo_fixture.dart`), widget tests with `noSuchMethod` fakes.

**Branch:** `feat/phase5-s2-diff-viewer-extras` from `main`. Version bump `0.1.18+19` → `0.1.19+20` in the final task.

**Process gotchas (repo conventions):**
- Flutter: `& "C:\Users\g.chirico\flutter\bin\flutter.bat"` (not on PATH); `flutter analyze` MUST run from the repo dir.
- NEVER blanket-format (`dart format lib test` rewrites ~180 pre-tall-style files). Format ONLY touched files with `dart.bat format <file> …`.
- Semantics in widget tests: `node.flagsCollection.isButton` (bool) / `.isSelected` (`Tristate.isTrue`, import dart:ui) — `hasFlag`/`containsSemantics` are deprecated in this Flutter.
- `main` tracks `origin/main` (zN3utr4l/GitOpen). NEVER `git pull` from `upstream` (samuu98/GitOpen). gh CLI: run `gh auth switch --hostname github.com --user zN3utr4l` before push/PR.
- Widgets that watch `appSettingsProvider` MUST have it overridden in widget tests (the default chain constructs the drift `AppDatabase`, which has no path-provider in tests). Each affected test file gets a tiny `_FakeSettingsStore`.

---

## File Structure

- Create: `lib/application/files/path_tree.dart` (pure `buildFileTree` + `PathTreeNode`)
- Create: `test/application/files/path_tree_test.dart`
- Modify: `lib/application/settings/app_settings.dart` (+`fileListsAsTree`)
- Modify: `lib/application/settings/app_settings_notifier.dart` (load + setter)
- Modify: `test/application/settings/app_settings_test.dart`
- Create: `lib/ui/common/file_list_mode_toggle.dart` (shared toggle widget)
- Modify: `lib/application/git/git_read_operations.dart` (recursive `getFileTree`, `getFileBytes`, `countDivergence`, `kFilePreviewMaxBytes`)
- Modify: `lib/infrastructure/git/git_cli_file_reader.dart` (recursive ls-tree, `getFileBytes`)
- Modify: `lib/infrastructure/git/git_cli_log_reader.dart` (`countDivergence`)
- Modify: `lib/infrastructure/git/git_process_runner.dart` (`runBytes`)
- Modify: `lib/infrastructure/git/git_cli_read_operations.dart` (facade delegations)
- Modify: `test/infrastructure/git/git_cli_read_operations_file_tree_test.dart` (recursive test)
- Create: `test/infrastructure/git/git_cli_read_operations_file_bytes_test.dart`
- Create: `test/infrastructure/git/git_cli_read_operations_divergence_test.dart`
- Create: `lib/domain/files/file_revision.dart` + `lib/domain/files/file_content.dart`
- Create: `lib/application/diff/image_preview.dart` (`isImagePath`, `formatBytes`)
- Create: `test/application/diff/image_preview_test.dart`
- Create: `lib/ui/common/image_diff_view.dart`
- Create: `test/ui/common/image_diff_view_test.dart`
- Modify: `lib/ui/bottom_panel/diff_view.dart` (image wiring)
- Modify: `lib/ui/working_copy/diff_preview_pane.dart` (image wiring)
- Modify: `lib/ui/working_copy/file_list.dart` + `lib/ui/working_copy/file_row.dart` (tree mode)
- Modify: `test/ui/working_copy/file_list_widget_test.dart`
- Modify: `lib/ui/bottom_panel/file_tree_view.dart` (tree/flat rework)
- Create: `test/ui/bottom_panel/file_tree_view_test.dart`
- Create: `lib/ui/dialogs/compare_refs_dialog.dart`
- Create: `test/ui/dialogs/compare_refs_dialog_test.dart`
- Modify: `lib/ui/sidebar/branch_tree_view.dart` (compare menu entries)
- Modify: `pubspec.yaml` (version)

---

### Task 1: Branch setup

- [ ] **Step 1: Create the branch and commit this plan**

```powershell
git -C D:\repos\Personal\GitOpen checkout -b feat/phase5-s2-diff-viewer-extras main
git -C D:\repos\Personal\GitOpen add docs/superpowers/plans/2026-06-11-phase5-s2-diff-viewer-extras.md
git -C D:\repos\Personal\GitOpen commit -m "docs(phase5): S2 implementation plan - diff & viewer extras"
```

---

### Task 2: Pure `buildFileTree` helper

**Files:**
- Create: `lib/application/files/path_tree.dart`
- Test: `test/application/files/path_tree_test.dart`

- [ ] **Step 1: Write the failing tests** at `test/application/files/path_tree_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/files/path_tree.dart';

List<String> names(List<PathTreeNode<String>> nodes) =>
    [for (final n in nodes) n.name];

void main() {
  group('buildFileTree', () {
    test('empty input yields an empty forest', () {
      expect(buildFileTree(<String>[], (p) => p), isEmpty);
    });

    test('flat files only: sorted case-insensitively, items attached', () {
      final nodes = buildFileTree(['b.txt', 'A.txt'], (p) => p);
      expect(names(nodes), ['A.txt', 'b.txt']);
      expect(nodes[0].item, 'A.txt');
      expect(nodes[0].isDirectory, isFalse);
      expect(nodes[0].path, 'A.txt');
    });

    test('folds directories, dirs sort before files', () {
      final nodes = buildFileTree(
        ['b.txt', 'a/y.txt', 'a/x.txt'],
        (p) => p,
      );
      expect(names(nodes), ['a', 'b.txt']);
      expect(nodes[0].isDirectory, isTrue);
      expect(nodes[0].path, 'a');
      expect(names(nodes[0].children), ['x.txt', 'y.txt']);
      expect(nodes[0].children[0].path, 'a/x.txt');
    });

    test('compresses single-child directory chains', () {
      final nodes = buildFileTree(
        ['src/app/main.dart', 'src/app/util.dart'],
        (p) => p,
      );
      expect(names(nodes), ['src/app']);
      expect(nodes[0].path, 'src/app');
      expect(names(nodes[0].children), ['main.dart', 'util.dart']);
    });

    test('does not compress a dir that also holds a file', () {
      final nodes = buildFileTree(
        ['a/b/x.txt', 'a/y.txt'],
        (p) => p,
      );
      expect(names(nodes), ['a']);
      expect(names(nodes[0].children), ['b', 'y.txt']);
      expect(nodes[0].children[0].path, 'a/b');
    });

    test('carries an arbitrary payload type', () {
      final nodes = buildFileTree(
        [(path: 'dir/f.txt', tag: 7)],
        (r) => r.path,
      );
      expect(nodes[0].children[0].item!.tag, 7);
    });
  });
}
```

- [ ] **Step 2: Run — must fail to compile** (`path_tree.dart` missing)

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/application/files/path_tree_test.dart`
Expected: compile error.

- [ ] **Step 3: Implement** `lib/application/files/path_tree.dart`:

```dart
/// A node in a folder tree folded from flat git paths ('/'-separated).
/// Directories carry [children]; file leaves carry the [item] they were
/// built from. Single-child directory chains are compressed into one node
/// whose [name] joins the segments ('src/app'), GitHub-style.
final class PathTreeNode<T> {
  const PathTreeNode({
    required this.name,
    required this.path,
    this.item,
    this.children = const [],
  });

  /// Display name. Compressed chains contain '/' ('src/app').
  final String name;

  /// Full path from the root ('src/app' or 'src/app/main.dart').
  final String path;

  /// The source item for file leaves; null for directories.
  final T? item;
  final List<PathTreeNode<T>> children;

  bool get isDirectory => item == null;
}

/// Folds flat paths into a directory forest: directories first, then files,
/// both sorted case-insensitively by name. Paths are assumed unique.
List<PathTreeNode<T>> buildFileTree<T>(
  Iterable<T> items,
  String Function(T) pathOf,
) {
  final root = _Dir<T>();
  for (final item in items) {
    final segments = pathOf(item).split('/');
    var dir = root;
    for (var i = 0; i < segments.length - 1; i++) {
      dir = dir.dirs.putIfAbsent(segments[i], _Dir<T>.new);
    }
    dir.files.add((name: segments.last, item: item));
  }
  return _emit(root, '');
}

final class _Dir<T> {
  final Map<String, _Dir<T>> dirs = {};
  final List<({String name, T item})> files = [];
}

List<PathTreeNode<T>> _emit<T>(_Dir<T> dir, String prefix) {
  final out = <PathTreeNode<T>>[];
  for (final entry in dir.dirs.entries) {
    var name = entry.key;
    var node = entry.value;
    var path = prefix.isEmpty ? name : '$prefix/$name';
    // Compress while the directory holds exactly one subdirectory and no
    // files — the chain reads as a single breadcrumb ('src/app').
    while (node.files.isEmpty && node.dirs.length == 1) {
      final only = node.dirs.entries.first;
      name = '$name/${only.key}';
      path = '$path/${only.key}';
      node = only.value;
    }
    out.add(PathTreeNode(name: name, path: path, children: _emit(node, path)));
  }
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final files = [
    for (final f in dir.files)
      PathTreeNode<T>(
        name: f.name,
        path: prefix.isEmpty ? f.name : '$prefix/${f.name}',
        item: f.item,
      ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return [...out, ...files];
}
```

- [ ] **Step 4: Run — tests pass**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/application/files/path_tree_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add lib/application/files/path_tree.dart test/application/files/path_tree_test.dart
git commit -m "feat(phase5): pure path-folding helper for tree file lists"
```

---

### Task 3: `fileListsAsTree` setting + shared toggle widget

**Files:**
- Modify: `lib/application/settings/app_settings.dart`
- Modify: `lib/application/settings/app_settings_notifier.dart`
- Create: `lib/ui/common/file_list_mode_toggle.dart`
- Test: `test/application/settings/app_settings_test.dart`

- [ ] **Step 1: Write the failing tests** — append inside the existing `AppSettingsState value object` group in `app_settings_test.dart`:

```dart
    test('fileListsAsTree defaults to false and copyWith overrides it', () {
      const state = AppSettingsState();
      expect(state.fileListsAsTree, isFalse);
      expect(state.copyWith(fileListsAsTree: true).fileListsAsTree, isTrue);
      // Untouched by unrelated copyWith calls.
      expect(state.copyWith(fontSize: 14).fileListsAsTree, isFalse);
    });
```

And a new top-level group (uses an inline fake store — no db) at the end of `main()`:

```dart
  group('AppSettingsNotifier fileListsAsTree', () {
    test('setFileListsAsTree updates state and persists the key', () async {
      final store = _RecordingStore();
      final notifier = AppSettingsNotifier(store);
      await notifier.setFileListsAsTree(true);
      expect(notifier.state.fileListsAsTree, isTrue);
      expect(store.puts['file_lists_as_tree'], isTrue);
    });

    test('load() reads a persisted true back', () async {
      final store = _RecordingStore()..seed['file_lists_as_tree'] = true;
      final notifier = AppSettingsNotifier(store);
      await Future<void>.delayed(Duration.zero); // let _load complete
      expect(notifier.state.fileListsAsTree, isTrue);
    });
  });
```

With this helper at the bottom of the file (import `package:gitopen/application/settings/settings_store.dart`):

```dart
final class _RecordingStore implements SettingsStore {
  final Map<String, dynamic> seed = {};
  final Map<String, dynamic> puts = {};

  @override
  Future<Map<String, dynamic>> readAll() async => seed;

  @override
  Future<void> put(String key, dynamic value) async => puts[key] = value;
}
```

- [ ] **Step 2: Run — fails** (`fileListsAsTree` undefined)

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/application/settings/app_settings_test.dart`

- [ ] **Step 3: Implement.** In `app_settings.dart` add to `AppSettingsState`:
  - constructor param `this.fileListsAsTree = false,` (after `autoRefresh`)
  - field doc + declaration:

```dart
  /// When true, the working-copy file list and the commit file list render
  /// as a folder tree instead of flat paths. Shared by both lists.
  final bool fileListsAsTree;
```

  - `copyWith` param `bool? fileListsAsTree,` and `fileListsAsTree: fileListsAsTree ?? this.fileListsAsTree,`
  - append `fileListsAsTree,` to `props`.

In `app_settings_notifier.dart`:
  - in `_load()` add `fileListsAsTree: (all['file_lists_as_tree'] as bool?) ?? false,`
  - add the setter (same shape as `setAutoRefresh`):

```dart
  // Positional bool retained so the method can be used as a void Function(bool)
  // tear-off for a Switch's onChanged callback in the settings UI.
  // ignore: avoid_positional_boolean_parameters
  Future<void> setFileListsAsTree(bool v) async {
    state = state.copyWith(fileListsAsTree: v);
    await _repo.put('file_lists_as_tree', v);
  }
```

- [ ] **Step 4: Create** `lib/ui/common/file_list_mode_toggle.dart` (same look as the `diff_prefs.dart` toggles):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Flat/tree toggle for file lists, backed by the persisted
/// `fileListsAsTree` setting (shared by the working-copy list and the
/// commit file list).
class FileListModeToggle extends ConsumerWidget {
  const FileListModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final asTree =
        ref.watch(appSettingsProvider.select((s) => s.fileListsAsTree));
    return Tooltip(
      message: asTree
          ? 'Tree view - click for a flat list'
          : 'Flat list - click for a tree view',
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        borderRadius: BorderRadius.circular(3),
        onTap: () => ref
            .read(appSettingsProvider.notifier)
            .setFileListsAsTree(!asTree),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            Icons.account_tree_outlined,
            size: 14,
            color: asTree ? palette.accentCurrent : palette.fg3,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run settings tests + analyze — clean**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/application/settings/app_settings_test.dart` then `& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze`

- [ ] **Step 6: Commit**

```powershell
git add lib/application/settings/app_settings.dart lib/application/settings/app_settings_notifier.dart lib/ui/common/file_list_mode_toggle.dart test/application/settings/app_settings_test.dart
git commit -m "feat(phase5): persisted fileListsAsTree setting + shared toggle"
```

---

### Task 4: Recursive `getFileTree`

**Files:**
- Modify: `lib/application/git/git_read_operations.dart:116-120`
- Modify: `lib/infrastructure/git/git_cli_file_reader.dart:89-124`
- Modify: `lib/infrastructure/git/git_cli_read_operations.dart:166-171`
- Test: `test/infrastructure/git/git_cli_read_operations_file_tree_test.dart`

- [ ] **Step 1: Write the failing real-git test** — append inside `main()` of the file-tree test file (reuse its existing fixture/`RepoLocation` helpers; if it has none, build inline as below — check the file first and follow its local pattern):

```dart
  test('recursive: true lists every blob with its full path', () async {
    final f = await RepoFixture.empty();
    try {
      await File(p.join(f.path, 'root.txt')).writeAsString('r\n');
      final nested = Directory(p.join(f.path, 'dir', 'sub'))
        ..createSync(recursive: true);
      await File(p.join(nested.path, 'deep.txt')).writeAsString('d\n');
      await Process.run('git', ['add', '-A'], workingDirectory: f.path);
      await Process.run(
        'git',
        ['commit', '-q', '-m', 'tree'],
        workingDirectory: f.path,
      );
      final head = await Process.run(
        'git',
        ['rev-parse', 'HEAD'],
        workingDirectory: f.path,
      );
      final sha = CommitSha((head.stdout as String).trim());

      final sut = GitCliReadOperations();
      final repo = RepoLocation(RepoId.newId(), f.path, 'fixture');
      final entries = await sut.getFileTree(repo, sha, '', recursive: true);

      final paths = entries.map((e) => e.fullPath).toList()..sort();
      expect(paths, ['dir/sub/deep.txt', 'root.txt']);
      // -r lists blobs only — no tree rows.
      expect(entries.any((e) => e.kind == FileTreeKind.tree), isFalse);
      expect(
        entries.firstWhere((e) => e.fullPath == 'dir/sub/deep.txt').name,
        'deep.txt',
      );
    } finally {
      await f.dispose();
    }
  });
```

(Add any missing imports the file doesn't already have: `dart:io`, `package:path/path.dart` as `p`, `RepoFixture` from `../../_helpers/repo_fixture.dart`, `CommitSha`, `RepoId`, `RepoLocation`, `FileTreeKind`.)

- [ ] **Step 2: Run — fails** (no `recursive` named param)

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/infrastructure/git/git_cli_read_operations_file_tree_test.dart`

- [ ] **Step 3: Implement.** Interface (`git_read_operations.dart`):

```dart
  /// Entries of [sha]'s tree at [path] (`git ls-tree -l`). With [recursive]
  /// every blob under [path] is listed with its full relative path and tree
  /// rows are omitted (`ls-tree -r`) — the shape `buildFileTree` folds.
  Future<List<FileTreeEntry>> getFileTree(
    RepoLocation repo,
    CommitSha sha,
    String path, {
    bool recursive = false,
  });
```

Reader (`git_cli_file_reader.dart`) — signature gains `{bool recursive = false}` and the args line becomes:

```dart
    final stdout = await _runner.run(repo.path, [
      'ls-tree',
      '-l',
      if (recursive) '-r',
      ref,
    ]);
```

Facade (`git_cli_read_operations.dart`):

```dart
  @override
  Future<List<FileTreeEntry>> getFileTree(
    RepoLocation repo,
    CommitSha sha,
    String path, {
    bool recursive = false,
  }) => _guard(() => _files.getFileTree(repo, sha, path, recursive: recursive));
```

- [ ] **Step 4: Run the file-tree tests — all pass (old + new)**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/infrastructure/git/git_cli_read_operations_file_tree_test.dart`

- [ ] **Step 5: Commit**

```powershell
git add lib/application/git/git_read_operations.dart lib/infrastructure/git/git_cli_file_reader.dart lib/infrastructure/git/git_cli_read_operations.dart test/infrastructure/git/git_cli_read_operations_file_tree_test.dart
git commit -m "feat(phase5): recursive getFileTree for tree file lists"
```

---

### Task 5: Working-copy file list tree mode

**Files:**
- Modify: `lib/ui/working_copy/file_row.dart:41-54` (new params) and `:294-299, :354-363` (use them)
- Modify: `lib/ui/working_copy/file_list.dart`
- Test: `test/ui/working_copy/file_list_widget_test.dart`

- [ ] **Step 1: Make the existing tests settings-safe.** `FileList` is about to watch `appSettingsProvider`; the test file's `_host` must override it. In `file_list_widget_test.dart` replace the `_host` helper with:

```dart
Widget _host(Widget child) {
  return ProviderScope(
    overrides: [
      appSettingsProvider.overrideWith(
        (ref) => AppSettingsNotifier(_FakeSettingsStore()),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [AppPalette.dark()]),
      home: Scaffold(
        body: SizedBox(width: 520, height: 360, child: child),
      ),
    ),
  );
}

final class _FakeSettingsStore implements SettingsStore {
  _FakeSettingsStore({this.seed = const {}});
  final Map<String, dynamic> seed;

  @override
  Future<Map<String, dynamic>> readAll() async => seed;

  @override
  Future<void> put(String key, dynamic value) async {}
}
```

(add imports: `package:gitopen/application/providers.dart`, `package:gitopen/application/settings/app_settings_notifier.dart`, `package:gitopen/application/settings/settings_store.dart`)

- [ ] **Step 2: Write the failing tree-mode test** — append inside `main()`:

```dart
  testWidgets('tree mode folds paths and collapses folders', (tester) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
    const a = WorkingFileEntry(
      path: 'src/app/a.dart',
      indexState: WorkingFileState.unmodified,
      workingTreeState: WorkingFileState.modified,
    );
    const b = WorkingFileEntry(
      path: 'src/app/b.dart',
      indexState: WorkingFileState.unmodified,
      workingTreeState: WorkingFileState.modified,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsNotifier(
              _FakeSettingsStore(seed: const {'file_lists_as_tree': true}),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: SizedBox(
              width: 520,
              height: 360,
              child: FileList(repo: repo, unstaged: const [a, b], staged: const []),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(); // settings _load

    // Compressed chain folder + leaf names (not full paths).
    expect(find.text('src/app'), findsOneWidget);
    expect(find.text('a.dart'), findsOneWidget);
    expect(find.text('src/app/a.dart'), findsNothing);

    // Collapsing the folder hides its leaves.
    await tester.tap(find.text('src/app'));
    await tester.pump();
    expect(find.text('a.dart'), findsNothing);
    expect(find.text('b.dart'), findsNothing);
  });
```

- [ ] **Step 3: Run — the new test fails** (no tree rendering yet); the pre-existing tests must still pass after the Step-1 host change.

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/working_copy/file_list_widget_test.dart`

- [ ] **Step 4: Add `displayName`/`indent` to `FileRow`.** In `file_row.dart`:

```dart
  const FileRow({
    required this.repo,
    required this.entry,
    required this.isStaged,
    this.displayName,
    this.indent = 0,
    super.key,
  });
  final RepoLocation repo;
  final WorkingFileEntry entry;
  final bool isStaged;

  /// Text shown for the file (tree mode shows the leaf name); defaults to
  /// the full path. Semantics keep the full path either way.
  final String? displayName;

  /// Extra left padding for tree indentation.
  final double indent;
```

In `_buildFileRowHeader` change the row `Padding` from `EdgeInsets.symmetric(horizontal: 12, vertical: 4)` to:

```dart
                padding: EdgeInsets.only(
                  left: 12 + widget.indent,
                  right: 12,
                  top: 4,
                  bottom: 4,
                ),
```

and the path `Text(widget.entry.path,` to `Text(widget.displayName ?? widget.entry.path,`.

- [ ] **Step 5: Rework `FileList`** (`file_list.dart`) — becomes stateful, watches the setting, renders flat or tree per section. Replace the `FileList` class (keep `HeaderAction`/`Header` unchanged):

```dart
class FileList extends ConsumerStatefulWidget {
  const FileList({
    required this.repo,
    required this.unstaged,
    required this.staged,
    super.key,
  });
  final RepoLocation repo;
  final List<WorkingFileEntry> unstaged;
  final List<WorkingFileEntry> staged;

  @override
  ConsumerState<FileList> createState() => _FileListState();
}

class _FileListState extends ConsumerState<FileList> {
  final Set<String> _collapsedUnstaged = {};
  final Set<String> _collapsedStaged = {};

  @override
  Widget build(BuildContext context) {
    final asTree =
        ref.watch(appSettingsProvider.select((s) => s.fileListsAsTree));
    final repo = widget.repo;
    final unstaged = widget.unstaged;
    final staged = widget.staged;
    return ListView(children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [FileListModeToggle()],
        ),
      ),
      Header(
        title: 'Unstaged (${unstaged.length})',
        actions: [
          HeaderAction(
            'Discard all',
            unstaged.isEmpty
                ? null
                : () => confirmAndDiscardAll(context, ref, repo, unstaged),
            danger: true,
          ),
          HeaderAction(
            'Stage all',
            unstaged.isEmpty
                ? null
                : () async {
                    await ref
                        .read(gitWriteOperationsProvider)
                        .stageFiles(repo, unstaged.map((e) => e.path).toList());
                    ref.invalidate(workingCopyStatusProvider(repo));
                  },
          ),
        ],
      ),
      ..._entryRows(
        unstaged,
        isStaged: false,
        asTree: asTree,
        collapsed: _collapsedUnstaged,
      ),
      Header(
        title: 'Staged (${staged.length})',
        actions: [
          HeaderAction(
            'Unstage all',
            staged.isEmpty
                ? null
                : () async {
                    await ref
                        .read(gitWriteOperationsProvider)
                        .unstageFiles(repo, staged.map((e) => e.path).toList());
                    ref.invalidate(workingCopyStatusProvider(repo));
                  },
          ),
        ],
      ),
      ..._entryRows(
        staged,
        isStaged: true,
        asTree: asTree,
        collapsed: _collapsedStaged,
      ),
    ]);
  }

  List<Widget> _entryRows(
    List<WorkingFileEntry> entries, {
    required bool isStaged,
    required bool asTree,
    required Set<String> collapsed,
  }) {
    if (!asTree) {
      return [
        for (final e in entries)
          FileRow(repo: widget.repo, entry: e, isStaged: isStaged),
      ];
    }
    final nodes = buildFileTree(entries, (e) => e.path);
    return _nodeRows(nodes, isStaged: isStaged, depth: 0, collapsed: collapsed);
  }

  List<Widget> _nodeRows(
    List<PathTreeNode<WorkingFileEntry>> nodes, {
    required bool isStaged,
    required int depth,
    required Set<String> collapsed,
  }) {
    final rows = <Widget>[];
    for (final node in nodes) {
      final item = node.item;
      if (item != null) {
        rows.add(FileRow(
          repo: widget.repo,
          entry: item,
          isStaged: isStaged,
          displayName: node.name,
          indent: depth * 14.0,
        ));
        continue;
      }
      final isCollapsed = collapsed.contains(node.path);
      rows.add(_DirRow(
        name: node.name,
        depth: depth,
        collapsed: isCollapsed,
        onTap: () => setState(() {
          if (!collapsed.add(node.path)) collapsed.remove(node.path);
        }),
      ));
      if (!isCollapsed) {
        rows.addAll(_nodeRows(
          node.children,
          isStaged: isStaged,
          depth: depth + 1,
          collapsed: collapsed,
        ));
      }
    }
    return rows;
  }
}

class _DirRow extends StatelessWidget {
  const _DirRow({
    required this.name,
    required this.depth,
    required this.collapsed,
    required this.onTap,
  });
  final String name;
  final int depth;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(
          left: 12 + depth * 14.0,
          right: 12,
          top: 3,
          bottom: 3,
        ),
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 14,
              color: palette.fg3,
            ),
            const SizedBox(width: 4),
            Icon(Icons.folder_outlined, size: 14, color: palette.accentTag),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.fg1,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

Add the imports `file_list.dart` now needs:

```dart
import 'package:gitopen/application/files/path_tree.dart';
import 'package:gitopen/ui/common/file_list_mode_toggle.dart';
```

- [ ] **Step 6: Run — file_list + file_row tests pass; analyze clean**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/working_copy` then `& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze`

- [ ] **Step 7: Commit**

```powershell
git add lib/ui/working_copy/file_list.dart lib/ui/working_copy/file_row.dart test/ui/working_copy/file_list_widget_test.dart
git commit -m "feat(phase5): tree mode for the working-copy file list"
```

---

### Task 6: Commit "File Tree" tab — real tree + flat toggle

**Files:**
- Modify: `lib/ui/bottom_panel/file_tree_view.dart`
- Test: `test/ui/bottom_panel/file_tree_view_test.dart` (new)

- [ ] **Step 1: Write the failing widget test** at `test/ui/bottom_panel/file_tree_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings_notifier.dart';
import 'package:gitopen/application/settings/settings_store.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/files/file_tree_entry.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/bottom_panel/file_tree_view.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final class _FakeReadOps implements GitReadOperations {
  @override
  Future<List<FileTreeEntry>> getFileTree(
    RepoLocation repo,
    CommitSha sha,
    String path, {
    bool recursive = false,
  }) async {
    expect(recursive, isTrue);
    return const [
      FileTreeEntry(
        name: 'deep.txt',
        fullPath: 'dir/sub/deep.txt',
        kind: FileTreeKind.blob,
        sizeBytes: 2,
      ),
      FileTreeEntry(
        name: 'root.txt',
        fullPath: 'root.txt',
        kind: FileTreeKind.blob,
        sizeBytes: 2,
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _FakeSettingsStore implements SettingsStore {
  _FakeSettingsStore(this.seed);
  final Map<String, dynamic> seed;

  @override
  Future<Map<String, dynamic>> readAll() async => seed;

  @override
  Future<void> put(String key, dynamic value) async {}
}

Future<void> _pump(WidgetTester tester, {required bool asTree}) async {
  final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitReadOperationsProvider.overrideWithValue(_FakeReadOps()),
        appSettingsProvider.overrideWith(
          (ref) => AppSettingsNotifier(
            _FakeSettingsStore({'file_lists_as_tree': asTree}),
          ),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Scaffold(
          body: SizedBox(
            width: 520,
            height: 400,
            child: FileTreeViewWidget(repo: repo, sha: CommitSha('a' * 40)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tree mode folds the recursive listing', (tester) async {
    await _pump(tester, asTree: true);
    expect(find.text('dir/sub'), findsOneWidget); // compressed chain
    expect(find.text('deep.txt'), findsOneWidget);
    expect(find.text('root.txt'), findsOneWidget);
    expect(find.text('dir/sub/deep.txt'), findsNothing);
  });

  testWidgets('flat mode lists full paths', (tester) async {
    await _pump(tester, asTree: false);
    expect(find.text('dir/sub/deep.txt'), findsOneWidget);
    expect(find.text('root.txt'), findsOneWidget);
    expect(find.text('dir/sub'), findsNothing);
  });
}
```

- [ ] **Step 2: Run — fails** (widget still renders the old root-level listing)

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/bottom_panel/file_tree_view_test.dart`

- [ ] **Step 3: Rework `file_tree_view.dart`.**

3a. Provider becomes recursive:

```dart
final AutoDisposeFutureProviderFamily<List<FileTreeEntry>,
        ({RepoLocation repo, CommitSha sha})> _fileTreeProvider =
    FutureProvider.family.autoDispose<List<FileTreeEntry>,
        ({RepoLocation repo, CommitSha sha})>((ref, key) async {
  final git = ref.watch(gitReadOperationsProvider);
  return git.getFileTree(key.repo, key.sha, '', recursive: true);
});
```

3b. `FileTreeViewWidget` becomes a `ConsumerStatefulWidget` holding `final Set<String> _collapsed = {};` and builds:

```dart
class FileTreeViewWidget extends ConsumerStatefulWidget {
  const FileTreeViewWidget({required this.repo, required this.sha, super.key});
  final RepoLocation repo;
  final CommitSha sha;

  @override
  ConsumerState<FileTreeViewWidget> createState() =>
      _FileTreeViewWidgetState();
}

class _FileTreeViewWidgetState extends ConsumerState<FileTreeViewWidget> {
  final Set<String> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final asTree =
        ref.watch(appSettingsProvider.select((s) => s.fileListsAsTree));
    final async = ref.watch(
      _fileTreeProvider((repo: widget.repo, sha: widget.sha)),
    );
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e',
          style: TextStyle(color: palette.accentErr))),
      data: (entries) {
        final children = <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [FileListModeToggle()],
            ),
          ),
        ];
        if (asTree) {
          final nodes = buildFileTree(entries, (e) => e.fullPath);
          children.addAll(_nodeRows(nodes, depth: 0));
        } else {
          final sorted = [...entries]..sort((a, b) =>
              a.fullPath.toLowerCase().compareTo(b.fullPath.toLowerCase()));
          children.addAll([
            for (final e in sorted)
              _FileRow(repo: widget.repo, entry: e, label: e.fullPath),
          ]);
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: children,
        );
      },
    );
  }

  List<Widget> _nodeRows(List<PathTreeNode<FileTreeEntry>> nodes,
      {required int depth}) {
    final rows = <Widget>[];
    for (final node in nodes) {
      final item = node.item;
      if (item != null) {
        rows.add(_FileRow(
          repo: widget.repo,
          entry: item,
          label: node.name,
          indent: depth * 14.0,
        ));
        continue;
      }
      final isCollapsed = _collapsed.contains(node.path);
      rows.add(_FolderRow(
        name: node.name,
        depth: depth,
        collapsed: isCollapsed,
        onTap: () => setState(() {
          if (!_collapsed.add(node.path)) _collapsed.remove(node.path);
        }),
      ));
      if (!isCollapsed) {
        rows.addAll(_nodeRows(node.children, depth: depth + 1));
      }
    }
    return rows;
  }
}
```

3c. `_FolderRow` — same shape as `_DirRow` from Task 5 (copy it here privately; it is 30 lines and the two views style folders identically today — do NOT extract a shared widget yet, the S4 polish slice owns consistency sweeps):

```dart
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.name,
    required this.depth,
    required this.collapsed,
    required this.onTap,
  });
  final String name;
  final int depth;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(
          left: 8 + depth * 14.0,
          right: 8,
          top: 3,
          bottom: 3,
        ),
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 14,
              color: palette.fg3,
            ),
            const SizedBox(width: 4),
            Icon(Icons.folder_outlined, size: 15, color: palette.accentTag),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.fg1,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

3d. `_FileRow` gains `label`/`indent` (kind icon, hover history button and context menu stay as-is). Field + constructor:

```dart
  const _FileRow({
    required this.repo,
    required this.entry,
    required this.label,
    this.indent = 0,
  });
  final RepoLocation repo;
  final FileTreeEntry entry;
  final String label;
  final double indent;
```

In its `build`, the row `Padding` becomes `EdgeInsets.only(left: 8 + widget.indent, right: 8, top: 3, bottom: 3)` and the name `Text(e.name,` becomes `Text(widget.label,`. Tree rows can no longer reach `_FileRow` (recursive listing has no `FileTreeKind.tree`), so delete the `e.kind == FileTreeKind.tree` icon/weight branches (keep submodule/symlink icons), and the `if (!_isFile) return row;` early-return can go — every entry is now interactive.

3e. Add imports:

```dart
import 'package:gitopen/application/files/path_tree.dart';
import 'package:gitopen/ui/common/file_list_mode_toggle.dart';
```

- [ ] **Step 4: Run — new widget tests pass; analyze clean**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/bottom_panel` then `& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze`

- [ ] **Step 5: Commit**

```powershell
git add lib/ui/bottom_panel/file_tree_view.dart test/ui/bottom_panel/file_tree_view_test.dart
git commit -m "feat(phase5): commit file list - real folder tree with flat toggle"
```

---

### Task 7: `FileRevision`/`FileContent` domain values + image pure helpers

**Files:**
- Create: `lib/domain/files/file_revision.dart`, `lib/domain/files/file_content.dart`
- Create: `lib/application/diff/image_preview.dart`
- Test: `test/application/diff/image_preview_test.dart`

- [ ] **Step 1: Write the failing pure tests** at `test/application/diff/image_preview_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/diff/image_preview.dart';

void main() {
  group('isImagePath', () {
    test('recognises the supported extensions case-insensitively', () {
      for (final p in [
        'a.png', 'b.jpg', 'c.JPEG', 'd.gif', 'e.webp', 'dir/f.BMP',
      ]) {
        expect(isImagePath(p), isTrue, reason: p);
      }
    });

    test('rejects non-image and extension-less paths', () {
      expect(isImagePath('a.txt'), isFalse);
      expect(isImagePath('archive.png.zip'), isFalse);
      expect(isImagePath('Makefile'), isFalse);
    });
  });

  group('formatBytes', () {
    test('formats B / KB / MB / GB', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(999), '999 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(20 * 1024 * 1024), '20.0 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
    });
  });
}
```

- [ ] **Step 2: Run — fails to compile**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/application/diff/image_preview_test.dart`

- [ ] **Step 3: Implement** `lib/application/diff/image_preview.dart`:

```dart
const Set<String> _imageExtensions = {
  'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp',
};

/// True when [path]'s extension is one the in-app image preview can render.
bool isImagePath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return false;
  return _imageExtensions.contains(path.substring(dot + 1).toLowerCase());
}

/// Human-readable byte size: '999 B', '1.0 KB', '20.0 MB', '3.0 GB'.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)} ${units[unit]}';
}
```

- [ ] **Step 4: Create the domain values.** `lib/domain/files/file_revision.dart`:

```dart
import 'package:equatable/equatable.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';

/// Which version of a file a byte-level read targets.
sealed class FileRevision extends Equatable {
  const FileRevision();

  @override
  List<Object?> get props => const [];
}

/// The blob committed at [commitSha].
final class FileRevisionAtCommit extends FileRevision {
  const FileRevisionAtCommit(this.commitSha);
  final CommitSha commitSha;

  @override
  List<Object?> get props => [commitSha];
}

/// The blob at [commitSha]'s FIRST parent — the "old" side of a
/// commit-vs-parent diff. Missing for root commits.
final class FileRevisionParentOfCommit extends FileRevision {
  const FileRevisionParentOfCommit(this.commitSha);
  final CommitSha commitSha;

  @override
  List<Object?> get props => [commitSha];
}

/// The blob at HEAD (old side of a staged diff).
final class FileRevisionHead extends FileRevision {
  const FileRevisionHead();
}

/// The blob staged in the index (stage 0).
final class FileRevisionIndex extends FileRevision {
  const FileRevisionIndex();
}

/// The bytes currently on disk in the working tree.
final class FileRevisionWorkingTree extends FileRevision {
  const FileRevisionWorkingTree();
}
```

`lib/domain/files/file_content.dart`:

```dart
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Result of a byte-level file read at some revision.
///
/// Three shapes: missing (`exists == false`), present but over the caller's
/// size cap (`exists, bytes == null`), and loaded (`bytes != null`).
final class FileContent extends Equatable {
  const FileContent({required this.exists, required this.sizeBytes, this.bytes});

  /// The path has no blob at the requested revision (added/deleted diff
  /// sides, root commit's parent, unborn HEAD).
  static const FileContent missing = FileContent(exists: false, sizeBytes: 0);

  final bool exists;
  final int sizeBytes;
  final Uint8List? bytes;

  /// Present but larger than the read's `maxBytes` cap.
  bool get tooLarge => exists && bytes == null;

  @override
  List<Object?> get props => [exists, sizeBytes, bytes];
}
```

- [ ] **Step 5: Run pure tests — pass; analyze clean**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/application/diff/image_preview_test.dart` then `& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze`

- [ ] **Step 6: Commit**

```powershell
git add lib/domain/files/file_revision.dart lib/domain/files/file_content.dart lib/application/diff/image_preview.dart test/application/diff/image_preview_test.dart
git commit -m "feat(phase5): file revision/content values + image preview helpers"
```

---

### Task 8: `getFileBytes` read op (runner bytes + reader + facade)

**Files:**
- Modify: `lib/infrastructure/git/git_process_runner.dart` (add `runBytes`)
- Modify: `lib/application/git/git_read_operations.dart` (interface + `kFilePreviewMaxBytes`)
- Modify: `lib/infrastructure/git/git_cli_file_reader.dart` (impl)
- Modify: `lib/infrastructure/git/git_cli_read_operations.dart` (facade)
- Test: `test/infrastructure/git/git_cli_read_operations_file_bytes_test.dart` (new)

- [ ] **Step 1: Write the failing real-git tests** at `test/infrastructure/git/git_cli_read_operations_file_bytes_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/files/file_revision.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import 'package:path/path.dart' as p;

import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) => RepoLocation(RepoId.newId(), f.path, 'fx');

  Future<String> git(RepoFixture f, List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: f.path);
    expect(r.exitCode, 0, reason: r.stderr.toString());
    return r.stdout.toString();
  }

  test('reads committed, parent, index and working-tree bytes', () async {
    final f = await RepoFixture.empty();
    try {
      final file = File(p.join(f.path, 'img.bin'));
      // v1 committed, then v2 committed, then v3 staged, then v4 on disk.
      await file.writeAsBytes([1, 0, 255]);
      await git(f, ['add', 'img.bin']);
      await git(f, ['commit', '-q', '-m', 'v1']);
      await file.writeAsBytes([2, 0, 254]);
      await git(f, ['add', 'img.bin']);
      await git(f, ['commit', '-q', '-m', 'v2']);
      final head = CommitSha((await git(f, ['rev-parse', 'HEAD'])).trim());
      await file.writeAsBytes([3, 0, 253]);
      await git(f, ['add', 'img.bin']);
      await file.writeAsBytes([4, 0, 252, 9]);

      final sut = GitCliReadOperations();
      final repo = loc(f);

      final atHead =
          await sut.getFileBytes(repo, FileRevisionAtCommit(head), 'img.bin');
      expect(atHead.exists, isTrue);
      expect(atHead.bytes, [2, 0, 254]);
      expect(atHead.sizeBytes, 3);

      final parent = await sut.getFileBytes(
          repo, FileRevisionParentOfCommit(head), 'img.bin');
      expect(parent.bytes, [1, 0, 255]);

      final index = await sut.getFileBytes(
          repo, const FileRevisionIndex(), 'img.bin');
      expect(index.bytes, [3, 0, 253]);

      final headRev = await sut.getFileBytes(
          repo, const FileRevisionHead(), 'img.bin');
      expect(headRev.bytes, [2, 0, 254]);

      final worktree = await sut.getFileBytes(
          repo, const FileRevisionWorkingTree(), 'img.bin');
      expect(worktree.bytes, [4, 0, 252, 9]);
      expect(worktree.sizeBytes, 4);
    } finally {
      await f.dispose();
    }
  });

  test('missing paths and a root commit parent report missing', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      final sut = GitCliReadOperations();
      final repo = loc(f);
      final root = CommitSha(f.headSha);

      final unknown = await sut.getFileBytes(
          repo, FileRevisionAtCommit(root), 'nope.png');
      expect(unknown.exists, isFalse);
      expect(unknown.sizeBytes, 0);

      final rootParent = await sut.getFileBytes(
          repo, FileRevisionParentOfCommit(root), 'file_0.txt');
      expect(rootParent.exists, isFalse);

      final noDisk = await sut.getFileBytes(
          repo, const FileRevisionWorkingTree(), 'nope.png');
      expect(noDisk.exists, isFalse);
    } finally {
      await f.dispose();
    }
  });

  test('maxBytes cap returns size only (no bytes)', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      final sut = GitCliReadOperations();
      final repo = loc(f);
      final capped = await sut.getFileBytes(
        repo,
        const FileRevisionHead(),
        'file_0.txt',
        maxBytes: 2,
      );
      expect(capped.exists, isTrue);
      expect(capped.bytes, isNull);
      expect(capped.tooLarge, isTrue);
      expect(capped.sizeBytes, greaterThan(2));
    } finally {
      await f.dispose();
    }
  });
}
```


- [ ] **Step 2: Run — fails to compile** (`getFileBytes` undefined)

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/infrastructure/git/git_cli_read_operations_file_bytes_test.dart`

- [ ] **Step 3: Implement.**

3a. `git_process_runner.dart` — add below `run`:

```dart
  /// Like [run] but returns raw stdout bytes (no UTF-8 decode) — blob
  /// content such as images would be corrupted by text decoding.
  Future<Uint8List> runBytes(String workingDir, List<String> args) async {
    final proc = await Process.start(
      executable,
      args,
      workingDirectory: workingDir,
      environment: buildGitEnvironment(),
    );
    final builder = BytesBuilder(copy: false);
    final stdoutF = proc.stdout.forEach(builder.add);
    final stderrF = proc.stderr.transform(utf8.decoder).join();
    final exitCode = await proc.exitCode;
    await stdoutF;
    final err = await stderrF;
    if (exitCode != 0) throw GitProcessException(args, exitCode, err);
    return builder.takeBytes();
  }
```

(add `import 'dart:typed_data';`)

3b. Interface (`git_read_operations.dart`) — add the constant near the top and the method to `GitReadOperations` (plus imports for `FileContent`/`FileRevision`):

```dart
/// Default byte cap for [GitReadOperations.getFileBytes] — image previews
/// above this render an explicit "too large" state instead of loading.
const int kFilePreviewMaxBytes = 20 * 1024 * 1024;
```

```dart
  /// Raw bytes of [path] at [revision]. Files larger than [maxBytes] return
  /// `exists`+size with null bytes (render an explicit "too large" state).
  /// A path with no blob at [revision] — added/deleted diff sides, a root
  /// commit's parent, unborn HEAD — returns [FileContent.missing], not an
  /// error.
  Future<FileContent> getFileBytes(
    RepoLocation repo,
    FileRevision revision,
    String path, {
    int maxBytes = kFilePreviewMaxBytes,
  });
```

3c. Reader (`git_cli_file_reader.dart`) — add these imports (infrastructure already imports the application interface elsewhere, e.g. `GitCliLogReader`):

```dart
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/domain/files/file_content.dart';
import 'package:gitopen/domain/files/file_revision.dart';
```

then the method:

```dart
  Future<FileContent> getFileBytes(
    RepoLocation repo,
    FileRevision revision,
    String path, {
    int maxBytes = kFilePreviewMaxBytes,
  }) async {
    if (revision is FileRevisionWorkingTree) {
      final file = File(p.join(repo.path, path));
      if (!file.existsSync()) return FileContent.missing;
      final size = await file.length();
      if (size > maxBytes) return FileContent(exists: true, sizeBytes: size);
      return FileContent(
        exists: true,
        sizeBytes: size,
        bytes: await file.readAsBytes(),
      );
    }
    final rev = switch (revision) {
      FileRevisionAtCommit(:final commitSha) => '${commitSha.value}:$path',
      FileRevisionParentOfCommit(:final commitSha) =>
        '${commitSha.value}^:$path',
      FileRevisionHead() => 'HEAD:$path',
      FileRevisionIndex() => ':$path',
      FileRevisionWorkingTree() => throw StateError('handled above'),
    };
    final int size;
    try {
      final out = await _runner.run(repo.path, ['cat-file', '-s', rev]);
      size = int.parse(out.trim());
    } on GitProcessException {
      // Any failure resolving the rev means "no blob there": unknown path,
      // root commit's missing parent, unborn HEAD. Callers render an
      // absent side, so this is a value, not an error.
      return FileContent.missing;
    }
    if (size > maxBytes) return FileContent(exists: true, sizeBytes: size);
    final bytes = await _runner.runBytes(repo.path, ['cat-file', 'blob', rev]);
    return FileContent(exists: true, sizeBytes: size, bytes: bytes);
  }
```

3d. Facade (`git_cli_read_operations.dart`):

```dart
  @override
  Future<FileContent> getFileBytes(
    RepoLocation repo,
    FileRevision revision,
    String path, {
    int maxBytes = kFilePreviewMaxBytes,
  }) => _guard(
    () => _files.getFileBytes(repo, revision, path, maxBytes: maxBytes),
  );
```

- [ ] **Step 4: Run — file-bytes tests pass; analyze clean**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/infrastructure/git/git_cli_read_operations_file_bytes_test.dart` then `& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze`

- [ ] **Step 5: Commit**

```powershell
git add lib/infrastructure/git/git_process_runner.dart lib/application/git/git_read_operations.dart lib/infrastructure/git/git_cli_file_reader.dart lib/infrastructure/git/git_cli_read_operations.dart test/infrastructure/git/git_cli_read_operations_file_bytes_test.dart
git commit -m "feat(phase5): getFileBytes read op with size cap"
```

---

### Task 9: `ImageDiffView` + wiring into both diff surfaces

**Files:**
- Create: `lib/ui/common/image_diff_view.dart`
- Modify: `lib/ui/bottom_panel/diff_view.dart:148-158`
- Modify: `lib/ui/working_copy/diff_preview_pane.dart:84-94`
- Test: `test/ui/common/image_diff_view_test.dart` (new)

- [ ] **Step 1: Write the failing widget test** at `test/ui/common/image_diff_view_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/files/file_content.dart';
import 'package:gitopen/domain/files/file_revision.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/image_diff_view.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Valid 1×1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk'
  '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

final class _FakeReadOps implements GitReadOperations {
  @override
  Future<FileContent> getFileBytes(
    RepoLocation repo,
    FileRevision revision,
    String path, {
    int maxBytes = kFilePreviewMaxBytes,
  }) async {
    return switch (revision) {
      FileRevisionParentOfCommit() => FileContent.missing,
      FileRevisionAtCommit() =>
        FileContent(exists: true, sizeBytes: _png.length, bytes: _png),
      _ => const FileContent(exists: true, sizeBytes: 30 * 1024 * 1024),
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitReadOperationsProvider.overrideWithValue(_FakeReadOps()),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Scaffold(body: SizedBox(width: 700, height: 400, child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
  final sha = CommitSha('a' * 40);

  testWidgets('renders a missing old side and an image new side',
      (tester) async {
    await _pump(
      tester,
      ImageDiffView(
        repo: repo,
        oldPath: 'img.png',
        newPath: 'img.png',
        oldRevision: FileRevisionParentOfCommit(sha),
        newRevision: FileRevisionAtCommit(sha),
      ),
    );
    expect(find.text('Old'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Not present'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    // Byte-size label of the new side.
    expect(find.textContaining(' B'), findsOneWidget);
  });

  testWidgets('renders an explicit too-large state', (tester) async {
    await _pump(
      tester,
      ImageDiffView(
        repo: repo,
        oldPath: 'img.png',
        newPath: 'img.png',
        oldRevision: const FileRevisionIndex(),
        newRevision: const FileRevisionWorkingTree(),
      ),
    );
    expect(find.textContaining('Too large to preview'), findsNWidgets(2));
    expect(find.byType(Image), findsNothing);
  });
}
```

- [ ] **Step 2: Run — fails to compile** (`ImageDiffView` missing)

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/common/image_diff_view_test.dart`

- [ ] **Step 3: Implement** `lib/ui/common/image_diff_view.dart`:

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/diff/image_preview.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/files/file_content.dart';
import 'package:gitopen/domain/files/file_revision.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final AutoDisposeFutureProviderFamily<FileContent,
        ({RepoLocation repo, FileRevision revision, String path})>
    _fileBytesProvider = FutureProvider.family.autoDispose<FileContent,
        ({RepoLocation repo, FileRevision revision, String path})>(
  (ref, key) => ref
      .watch(gitReadOperationsProvider)
      .getFileBytes(key.repo, key.revision, key.path),
);

/// Old/new side-by-side preview for a binary image file: checkerboard
/// backdrop, byte-size + pixel-dimension labels, explicit states for a
/// missing side and for files over the preview size cap.
class ImageDiffView extends StatelessWidget {
  const ImageDiffView({
    required this.repo,
    required this.oldPath,
    required this.newPath,
    required this.oldRevision,
    required this.newRevision,
    super.key,
  });
  final RepoLocation repo;
  final String oldPath;
  final String newPath;
  final FileRevision oldRevision;
  final FileRevision newRevision;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _ImageSide(
              label: 'Old',
              repo: repo,
              path: oldPath,
              revision: oldRevision,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ImageSide(
              label: 'New',
              repo: repo,
              path: newPath,
              revision: newRevision,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageSide extends ConsumerWidget {
  const _ImageSide({
    required this.label,
    required this.repo,
    required this.path,
    required this.revision,
  });
  final String label;
  final RepoLocation repo;
  final String path;
  final FileRevision revision;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(
      _fileBytesProvider((repo: repo, revision: revision, path: path)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: palette.fg2,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (e, _) => Text(
            'Error: $e',
            style: TextStyle(color: palette.accentErr, fontSize: 11.5),
          ),
          data: (content) => _body(context, content),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, FileContent content) {
    final palette = AppPalette.of(context);
    if (!content.exists) {
      return Text(
        'Not present',
        style: TextStyle(
          color: palette.fg3,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    if (content.tooLarge) {
      return Text(
        'Too large to preview (${formatBytes(content.sizeBytes)})',
        style: TextStyle(
          color: palette.fg2,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    final bytes = content.bytes!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(4),
          ),
          clipBehavior: Clip.antiAlias,
          child: CustomPaint(
            painter: _CheckerboardPainter(
              light: palette.bg2,
              dark: palette.bg4,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              formatBytes(content.sizeBytes),
              style: TextStyle(color: palette.fg2, fontSize: 11),
            ),
            const SizedBox(width: 8),
            _DimensionsLabel(bytes: bytes),
          ],
        ),
      ],
    );
  }
}

/// 'W × H px', resolved by decoding the image header asynchronously.
/// Renders nothing until (or unless) the decode succeeds.
class _DimensionsLabel extends StatelessWidget {
  const _DimensionsLabel({required this.bytes});
  final Uint8List bytes;

  Future<({int width, int height})> _decode() async {
    final image = await ui.decodeImageFromList(bytes);
    final size = (width: image.width, height: image.height);
    image.dispose();
    return size;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return FutureBuilder(
      future: _decode(),
      builder: (context, snapshot) {
        final size = snapshot.data;
        if (size == null) return const SizedBox.shrink();
        return Text(
          '${size.width} × ${size.height} px',
          style: TextStyle(color: palette.fg2, fontSize: 11),
        );
      },
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter({required this.light, required this.dark});
  final Color light;
  final Color dark;

  static const double _square = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final lightPaint = Paint()..color = light;
    final darkPaint = Paint()..color = dark;
    canvas.drawRect(Offset.zero & size, lightPaint);
    for (var y = 0; y * _square < size.height; y++) {
      for (var x = y.isEven ? 1 : 0; x * _square < size.width; x += 2) {
        canvas.drawRect(
          Rect.fromLTWH(x * _square, y * _square, _square, _square),
          darkPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerboardPainter oldDelegate) =>
      light != oldDelegate.light || dark != oldDelegate.dark;
}
```

- [ ] **Step 4: Wire the commit diff** (`diff_view.dart`). Replace the `if (file.isBinary) Padding(…)` block in `_FileDiffBlockState.build` with:

```dart
          if (file.isBinary)
            isImagePath(file.path)
                ? ImageDiffView(
                    repo: widget.repo,
                    oldPath: file.oldPath ?? file.path,
                    newPath: file.path,
                    oldRevision: FileRevisionParentOfCommit(widget.sha),
                    newRevision: FileRevisionAtCommit(widget.sha),
                  )
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Binary file (no preview)',
                      style: TextStyle(
                        color: palette.fg2,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
```

Add imports to `diff_view.dart`:

```dart
import 'package:gitopen/application/diff/image_preview.dart';
import 'package:gitopen/domain/files/file_revision.dart';
import 'package:gitopen/ui/common/image_diff_view.dart';
```

- [ ] **Step 5: Wire the working-copy preview** (`diff_preview_pane.dart`). Replace the `if (fileDiff.isBinary) { return Center(…); }` block with:

```dart
          if (fileDiff.isBinary) {
            if (isImagePath(sel.path)) {
              return ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  DiffHeader(path: sel.path, fileDiff: fileDiff),
                  ImageDiffView(
                    repo: repo,
                    oldPath: fileDiff.oldPath ?? sel.path,
                    newPath: sel.path,
                    oldRevision: sel.staged
                        ? const FileRevisionHead()
                        : const FileRevisionIndex(),
                    newRevision: sel.staged
                        ? const FileRevisionIndex()
                        : const FileRevisionWorkingTree(),
                  ),
                ],
              );
            }
            return Center(
              child: Text(
                'Binary file (no preview)',
                style: TextStyle(
                  color: palette.fg2,
                  fontStyle: FontStyle.italic,
                ),
              ),
            );
          }
```

Add imports to `diff_preview_pane.dart`:

```dart
import 'package:gitopen/application/diff/image_preview.dart';
import 'package:gitopen/domain/files/file_revision.dart';
import 'package:gitopen/ui/common/image_diff_view.dart';
```

- [ ] **Step 6: Run — image tests pass; analyze clean**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/common/image_diff_view_test.dart` then `& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze`

- [ ] **Step 7: Commit**

```powershell
git add lib/ui/common/image_diff_view.dart lib/ui/bottom_panel/diff_view.dart lib/ui/working_copy/diff_preview_pane.dart test/ui/common/image_diff_view_test.dart
git commit -m "feat(phase5): side-by-side image diff previews"
```

---

### Task 10: `countDivergence` read op

**Files:**
- Modify: `lib/application/git/git_read_operations.dart` (interface)
- Modify: `lib/infrastructure/git/git_cli_log_reader.dart` (impl)
- Modify: `lib/infrastructure/git/git_cli_read_operations.dart` (facade)
- Test: `test/infrastructure/git/git_cli_read_operations_divergence_test.dart` (new)

- [ ] **Step 1: Write the failing real-git test**:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import 'package:path/path.dart' as p;

import '../../_helpers/repo_fixture.dart';

void main() {
  test('countDivergence reports commits unique to each side', () async {
    // withBranches: master(3 commits) + feature(master tip + 1 commit).
    final f = await RepoFixture.withBranches();
    try {
      // Advance master by one more commit so BOTH sides have unique commits.
      await File(p.join(f.path, 'm.txt')).writeAsString('m\n');
      await Process.run('git', ['add', '-A'], workingDirectory: f.path);
      await Process.run(
        'git',
        ['commit', '-q', '-m', 'master only'],
        workingDirectory: f.path,
      );
      String sha(String ref) {
        final r = Process.runSync(
          'git',
          ['rev-parse', ref],
          workingDirectory: f.path,
        );
        return (r.stdout as String).trim();
      }

      final sut = GitCliReadOperations();
      final repo = RepoLocation(RepoId.newId(), f.path, 'fx');
      final d = await sut.countDivergence(
        repo,
        CommitSha(sha('master')),
        CommitSha(sha('feature')),
      );
      expect(d.left, 1); // 'master only'
      expect(d.right, 1); // 'on feature'

      final same = await sut.countDivergence(
        repo,
        CommitSha(sha('master')),
        CommitSha(sha('master')),
      );
      expect(same.left, 0);
      expect(same.right, 0);
    } finally {
      await f.dispose();
    }
  });
}
```

- [ ] **Step 2: Run — fails to compile**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/infrastructure/git/git_cli_read_operations_divergence_test.dart`

- [ ] **Step 3: Implement.** Interface:

```dart
  /// Symmetric divergence between two commits
  /// (`git rev-list --left-right --count a...b`): [left] = commits
  /// reachable only from [a], [right] = only from [b].
  Future<({int left, int right})> countDivergence(
    RepoLocation repo,
    CommitSha a,
    CommitSha b,
  );
```

`git_cli_log_reader.dart`:

```dart
  Future<({int left, int right})> countDivergence(
    RepoLocation repo,
    CommitSha a,
    CommitSha b,
  ) async {
    final out = await _runner.run(repo.path, [
      'rev-list',
      '--left-right',
      '--count',
      '${a.value}...${b.value}',
    ]);
    final parts = out.trim().split(RegExp(r'\s+'));
    return (left: int.parse(parts[0]), right: int.parse(parts[1]));
  }
```

Facade:

```dart
  @override
  Future<({int left, int right})> countDivergence(
    RepoLocation repo,
    CommitSha a,
    CommitSha b,
  ) => _guard(() => _log.countDivergence(repo, a, b));
```

- [ ] **Step 4: Run — passes; analyze clean**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/infrastructure/git/git_cli_read_operations_divergence_test.dart` then `& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze`

- [ ] **Step 5: Commit**

```powershell
git add lib/application/git/git_read_operations.dart lib/infrastructure/git/git_cli_log_reader.dart lib/infrastructure/git/git_cli_read_operations.dart test/infrastructure/git/git_cli_read_operations_divergence_test.dart
git commit -m "feat(phase5): countDivergence read op for ref comparison"
```

---

### Task 11: Compare-refs dialog + branch menu entries

**Files:**
- Create: `lib/ui/dialogs/compare_refs_dialog.dart`
- Modify: `lib/ui/sidebar/branch_tree_view.dart` (menu entries + handlers)
- Test: `test/ui/dialogs/compare_refs_dialog_test.dart` (new)

- [ ] **Step 1: Write the failing widget test** at `test/ui/dialogs/compare_refs_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/commits/commit_signature.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/domain/diff/diff_result.dart';
import 'package:gitopen/domain/diff/diff_spec.dart';
import 'package:gitopen/domain/diff/file_diff.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/compare_refs_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final _fromSha = CommitSha('a' * 40);
final _toSha = CommitSha('b' * 40);

CommitInfo _commit(String shaChar, String summary) {
  final sig = CommitSignature('Ada', 'a@x.io', DateTime.utc(2026, 6));
  return CommitInfo(
    sha: CommitSha(shaChar * 40),
    parentShas: const [],
    author: sig,
    committer: sig,
    summary: summary,
    message: summary,
  );
}

final class _FakeReadOps implements GitReadOperations {
  @override
  Future<({int left, int right})> countDivergence(
    RepoLocation repo,
    CommitSha a,
    CommitSha b,
  ) async => (left: 1, right: 2);

  @override
  Stream<CommitInfo> getCommits(RepoLocation repo, CommitQuery query) {
    if (query.refSpec == '${_toSha.value}..${_fromSha.value}') {
      return Stream.fromIterable([_commit('c', 'only on from')]);
    }
    return Stream.fromIterable([_commit('d', 'only on to')]);
  }

  @override
  Future<DiffResult> getDiff(
    RepoLocation repo,
    DiffSpec spec, {
    bool ignoreWhitespace = false,
  }) async {
    expect(spec, DiffSpecCommitVsCommit(_fromSha, _toSha));
    return const DiffResult(files: [
      FileDiff(
        path: 'lib/x.dart',
        changeKind: FileChangeKind.modified,
        isBinary: false,
        linesAdded: 1,
        linesDeleted: 0,
        hunks: [
          DiffHunk(
            oldStart: 1,
            oldCount: 0,
            newStart: 1,
            newCount: 1,
            header: '@@ -1,0 +1,1 @@',
            lines: [
              DiffLine(kind: DiffLineKind.addition, content: 'hello', newLine: 1),
            ],
          ),
        ],
      ),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  testWidgets('shows counts, both commit lists and the combined diff',
      (tester) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
    final from = Branch(
      name: 'main',
      fullName: 'refs/heads/main',
      isRemote: false,
      isCurrent: true,
      ahead: 0,
      behind: 0,
      tipSha: _fromSha,
    );
    final to = Branch(
      name: 'feature',
      fullName: 'refs/heads/feature',
      isRemote: false,
      isCurrent: false,
      ahead: 0,
      behind: 0,
      tipSha: _toSha,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitReadOperationsProvider.overrideWithValue(_FakeReadOps()),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => CompareRefsDialog.show(
                    context,
                    repo: repo,
                    from: from,
                    to: to,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('main'), findsWidgets);
    expect(find.textContaining('feature'), findsWidgets);
    expect(find.text('Only on main (1)'), findsOneWidget);
    expect(find.text('Only on feature (2)'), findsOneWidget);
    expect(find.text('only on from'), findsOneWidget);
    expect(find.text('only on to'), findsOneWidget);
    expect(find.text('lib/x.dart'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — fails to compile**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/dialogs/compare_refs_dialog_test.dart`

- [ ] **Step 3: Implement** `lib/ui/dialogs/compare_refs_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/diff/image_preview.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/diff/diff_result.dart';
import 'package:gitopen/domain/diff/diff_spec.dart';
import 'package:gitopen/domain/files/file_revision.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/bottom_panel/diff_syntax.dart';
import 'package:gitopen/ui/common/image_diff_view.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/diff_preview_pane.dart'
    show DiffHeader, HunkBlock;
import 'package:intl/intl.dart';

typedef _Key = ({RepoLocation repo, CommitSha from, CommitSha to});

final AutoDisposeFutureProviderFamily<({int left, int right}), _Key>
    _divergenceProvider =
    FutureProvider.family.autoDispose<({int left, int right}), _Key>(
  (ref, key) => ref
      .watch(gitReadOperationsProvider)
      .countDivergence(key.repo, key.from, key.to),
);

/// Commits reachable only from `from` (left list). Capped at 100.
final AutoDisposeFutureProviderFamily<List<CommitInfo>, _Key>
    _onlyFromProvider =
    FutureProvider.family.autoDispose<List<CommitInfo>, _Key>(
  (ref, key) => ref
      .watch(gitReadOperationsProvider)
      .getCommits(
        key.repo,
        CommitQuery(refSpec: '${key.to.value}..${key.from.value}', take: 100),
      )
      .toList(),
);

/// Commits reachable only from `to` (right list). Capped at 100.
final AutoDisposeFutureProviderFamily<List<CommitInfo>, _Key> _onlyToProvider =
    FutureProvider.family.autoDispose<List<CommitInfo>, _Key>(
  (ref, key) => ref
      .watch(gitReadOperationsProvider)
      .getCommits(
        key.repo,
        CommitQuery(refSpec: '${key.from.value}..${key.to.value}', take: 100),
      )
      .toList(),
);

final AutoDisposeFutureProviderFamily<DiffResult, _Key> _compareDiffProvider =
    FutureProvider.family.autoDispose<DiffResult, _Key>(
  (ref, key) => ref
      .watch(gitReadOperationsProvider)
      .getDiff(key.repo, DiffSpecCommitVsCommit(key.from, key.to)),
);

/// Two-ref comparison: divergence counts, the two unique-commit lists and
/// the combined `from..to` diff.
class CompareRefsDialog extends ConsumerWidget {
  const CompareRefsDialog({
    required this.repo,
    required this.from,
    required this.to,
    super.key,
  });
  final RepoLocation repo;
  final Branch from;
  final Branch to;

  /// Both branches must have a [Branch.tipSha]; callers guard.
  static Future<void> show(
    BuildContext context, {
    required RepoLocation repo,
    required Branch from,
    required Branch to,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => CompareRefsDialog(repo: repo, from: from, to: to),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final _Key key = (repo: repo, from: from.tipSha!, to: to.tipSha!);
    final divergence = ref.watch(_divergenceProvider(key));
    return AppDialog(
      title: 'Compare ${from.name} ⟷ ${to.name}',
      width: 920,
      content: SizedBox(
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 200,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _CommitListColumn(
                      title:
                          'Only on ${from.name} (${divergence.valueOrNull?.left ?? '…'})',
                      provider: _onlyFromProvider(key),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _CommitListColumn(
                      title:
                          'Only on ${to.name} (${divergence.valueOrNull?.right ?? '…'})',
                      provider: _onlyToProvider(key),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'CHANGES (${from.name} → ${to.name})',
              style: TextStyle(
                color: palette.fg3,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(child: _CompareDiff(diffKey: key)),
          ],
        ),
      ),
      actions: [
        AppButton.secondary(
          label: 'Close',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }
}

class _CommitListColumn extends ConsumerWidget {
  const _CommitListColumn({required this.title, required this.provider});
  final String title;
  final AutoDisposeFutureProvider<List<CommitInfo>> provider;

  static final _dateFmt = DateFormat('yyyy-MM-dd');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(provider);
    return Container(
      decoration: BoxDecoration(
        color: palette.bg1,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: palette.bg3,
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: Text(
              title,
              style: TextStyle(
                color: palette.fg1,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Error: $e',
                  style: TextStyle(color: palette.accentErr, fontSize: 11.5),
                ),
              ),
              data: (commits) => commits.isEmpty
                  ? Center(
                      child: Text(
                        'No unique commits',
                        style: TextStyle(
                          color: palette.fg3,
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: commits.length,
                      itemBuilder: (_, i) {
                        final c = commits[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          child: Row(
                            children: [
                              Text(
                                c.sha.short(),
                                style: TextStyle(
                                  color: palette.accentRemote,
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  c.summary,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: palette.fg0,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _dateFmt.format(c.author.when.toLocal()),
                                style: TextStyle(
                                  color: palette.fg3,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompareDiff extends ConsumerWidget {
  const _CompareDiff({required this.diffKey});
  final _Key diffKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(_compareDiffProvider(diffKey));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Error: $e',
          style: TextStyle(color: palette.accentErr, fontSize: 11.5),
        ),
      ),
      data: (d) => d.files.isEmpty
          ? Center(
              child: Text(
                'No changes between the two refs',
                style: TextStyle(
                  color: palette.fg3,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          : ListView(
              children: [
                for (final f in d.files) ...[
                  DiffHeader(path: f.path, fileDiff: f),
                  if (f.isBinary)
                    isImagePath(f.path)
                        ? ImageDiffView(
                            repo: diffKey.repo,
                            oldPath: f.oldPath ?? f.path,
                            newPath: f.path,
                            oldRevision: FileRevisionAtCommit(diffKey.from),
                            newRevision: FileRevisionAtCommit(diffKey.to),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'Binary file (no preview)',
                              style: TextStyle(
                                color: palette.fg2,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          )
                  else
                    for (final h in f.hunks)
                      HunkBlock(hunk: h, language: languageForPath(f.path)),
                ],
              ],
            ),
    );
  }
}
```

- [ ] **Step 4: Add the menu entries** in `branch_tree_view.dart`.

4a. Inside the existing `if (!isCurrent) ...const [` spread, add after the `interactive_rebase` item (before the `AppMenuDivider()`):

```dart
        AppMenuItem(
          value: 'compare_current',
          label: 'Compare with current…',
          icon: Icons.compare,
        ),
```

4b. Right after that whole `if (!isCurrent)` spread (so it appears for every branch, current included), add:

```dart
      const AppMenuItem(
        value: 'compare_with',
        label: 'Compare with…',
        icon: Icons.compare_arrows,
      ),
      const AppMenuDivider(),
```

4c. Handlers — add cases to the `switch (selected)`:

```dart
      case 'compare_current':
        final tip = branch.tipSha;
        if (tip == null) return;
        final locals =
            await ref.read(localBranchesProvider(widget.repo).future);
        final currents = locals.where((b) => b.isCurrent && b.tipSha != null);
        if (currents.isEmpty || !context.mounted) return;
        await CompareRefsDialog.show(
          context,
          repo: widget.repo,
          from: currents.first,
          to: branch,
        );

      case 'compare_with':
        if (branch.tipSha == null) return;
        final all = await ref.read(branchesProvider(widget.repo).future);
        final candidates = {
          for (final b in all)
            if (b.fullName != branch.fullName && b.tipSha != null) b.name: b,
        };
        if (!context.mounted) return;
        final picked = await showDialog<String>(
          context: context,
          builder: (_) => BranchPickerDialog(
            title: 'Compare "${branch.name}" with…',
            branches: candidates.keys.toList(),
          ),
        );
        final other = candidates[picked];
        if (other == null || !context.mounted) return;
        await CompareRefsDialog.show(
          context,
          repo: widget.repo,
          from: branch,
          to: other,
        );
```

4d. Add imports to `branch_tree_view.dart`:

```dart
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/dialogs/compare_refs_dialog.dart';
import 'package:gitopen/ui/toolbar/branch_picker_dialog.dart';
```

- [ ] **Step 5: Run — dialog test passes; sidebar tests still pass; analyze clean**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/dialogs/compare_refs_dialog_test.dart test/ui/sidebar` then `& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze`

- [ ] **Step 6: Commit**

```powershell
git add lib/ui/dialogs/compare_refs_dialog.dart lib/ui/sidebar/branch_tree_view.dart test/ui/dialogs/compare_refs_dialog_test.dart
git commit -m "feat(phase5): compare-refs view from the branch context menu"
```

---

### Task 12: Verification and PR

- [ ] **Step 1: Bump version** in `pubspec.yaml`: `0.1.18+19` → `0.1.19+20` (CI version-check requires a new unreleased version when `lib/` changes).
- [ ] **Step 2: Format touched files only** (`dart.bat format <each touched lib/test file>`) — NEVER blanket-format.
- [ ] **Step 3: Full verification**

```powershell
& "C:\Users\g.chirico\flutter\bin\flutter.bat" test -j 2
& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze
git diff --check
```

Expected: full suite green (605 pre-S2 tests + the ~20 added here), analyze clean, no whitespace errors. Known flake note: two real-git fixture tests (getCommits skip/take; getFileHistory author) may flake ONLY under full-suite parallel load — if one fails, capture the output, rerun the single file to confirm it passes alone.

- [ ] **Step 4: Commit, push, PR, merge on green**

```powershell
gh auth switch --hostname github.com --user zN3utr4l
git add pubspec.yaml docs/superpowers/plans/2026-06-11-phase5-s2-diff-viewer-extras.md
git commit -m "chore(phase5): bump version to 0.1.19"
git push -u origin feat/phase5-s2-diff-viewer-extras
gh pr create --repo zN3utr4l/GitOpen --base main --title "feat(phase5): S2 - diff & viewer extras" --body "<summary: image diff, tree file lists, compare refs + spec link docs/superpowers/specs/2026-06-11-phase5-complete-beautiful-design.md>"
gh pr checks --repo zN3utr4l/GitOpen --watch   # merge with: gh pr merge --repo zN3utr4l/GitOpen --merge --delete-branch
```

IMPORTANT: this clone has an `upstream` remote (samuu98/GitOpen). Always pass `--repo zN3utr4l/GitOpen` to gh, and never `git pull` without confirming the branch tracks `origin`.
