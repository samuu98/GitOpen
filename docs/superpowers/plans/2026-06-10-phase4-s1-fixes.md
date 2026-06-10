# Phase 4 — S1 Real Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the four real bugs from the Phase 4 audit (remote checkout detaches HEAD, UI tags always lightweight, safeCheckout bypassed by menus, push_tag/per-remote-fetch bypass the facade) and instrument the two flaky tests.

**Architecture:** All git behaviour flows UI → `GitActionsController` → `GitActionsService` → `GitWriteOperations` (facade `GitCliWriteOperations` → per-concern writers). New ops follow that chain end-to-end. UI checkout logic centralizes in `safe_checkout.dart` (`checkoutRef` handles the remote→local-tracking decision; `safeCheckout` handles the dirty tree and now delegates the final checkout to the controller).

**Tech Stack:** Flutter/Dart, riverpod, flutter_test with real-git `RepoFixture` fixtures (`test/_helpers/repo_fixture.dart`).

**Branch:** `fix/phase4-s1-fixes` (already created; spec committed on it).

**Commands** (run from `D:\repos\Personal\GitOpen`; flutter is NOT on PATH):
- Test: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test <path>`
- Full suite: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test`
- Analyze: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze`
- Format: `dart.bat format <files>`

## File Structure

| File | Change |
|---|---|
| `lib/application/git/git_write_operations.dart` | + `checkoutTrack` to interface |
| `lib/infrastructure/git/git_cli_ref_writer.dart` | + `checkoutTrack` impl |
| `lib/infrastructure/git/git_cli_write_operations.dart` | + `checkoutTrack` delegation |
| `lib/application/git/git_actions_service.dart` | + `checkoutTrack`, `pushTag`, `fetchRemote` |
| `lib/ui/git/git_actions_controller.dart` | + `checkoutTrack`, `pushTag`, `fetchRemote` |
| `lib/ui/checkout/safe_checkout.dart` | + `checkoutRef`, `localBranchNameFor`; `safeCheckout` goes through controller |
| `lib/ui/sidebar/branch_tree_view.dart` | menu label + both checkout paths → `checkoutRef` |
| `lib/ui/sidebar/tag_row.dart` | menu checkout → `safeCheckout`; push_tag → controller |
| `lib/ui/sidebar/remotes_section.dart` | fetch → controller; delete `_fetchRemote` |
| `lib/ui/commit_graph/commit_graph_panel.dart` | ref-pill double-tap → `checkoutRef`; tag_here → `TagCreateDialog` |
| `lib/ui/toolbar/branch_dropdown.dart` | switch-branch → `safeCheckout` |
| `lib/ui/dialogs/tag_create_dialog.dart` | NEW: name + optional message dialog |
| `test/infrastructure/git/git_cli_write_operations_checkout_track_test.dart` | NEW |
| `test/infrastructure/git/git_cli_write_operations_tag_test.dart` | + annotated-tag test |
| `test/application/git/git_actions_service_test.dart` | + pushTag/fetchRemote tests (extend `_FakeWrite`) |
| `test/application/git/git_actions_service_local_test.dart` | + checkoutTrack mapping test |
| `test/ui/checkout/local_branch_name_test.dart` | NEW |
| `test/ui/dialogs/tag_create_dialog_test.dart` | NEW |
| `test/_helpers/flake_capture.dart` | NEW |
| `test/infrastructure/git/git_cli_read_operations_commits_test.dart` | wrap flaky test |
| `test/infrastructure/git/git_cli_read_operations_file_history_test.dart` | wrap flaky test |
| `pubspec.yaml` | version bump (CI version-check) |

---

### Task 1: `checkoutTrack` backend (interface → writer → facade → service → controller)

**Files:**
- Modify: `lib/application/git/git_write_operations.dart` (after `checkout`, ~line 78)
- Modify: `lib/infrastructure/git/git_cli_ref_writer.dart` (after `checkout`, ~line 34)
- Modify: `lib/infrastructure/git/git_cli_write_operations.dart` (after `checkout`, ~line 116)
- Modify: `lib/application/git/git_actions_service.dart` (after `checkout`, ~line 272)
- Modify: `lib/ui/git/git_actions_controller.dart` (after `checkout`, ~line 189)
- Test: `test/infrastructure/git/git_cli_write_operations_checkout_track_test.dart` (new)
- Test: `test/application/git/git_actions_service_local_test.dart`

- [ ] **Step 1: Write the failing infra test**

Create `test/infrastructure/git/git_cli_write_operations_checkout_track_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';

import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) => RepoLocation(RepoId.newId(), f.path, 't');

  /// Local repo (own master commit) with a file remote that has master +
  /// feature, already fetched so refs/remotes/origin/* exist.
  Future<(RepoFixture local, RepoFixture origin)> fixture() async {
    final origin = await RepoFixture.withBranches();
    final local = await RepoFixture.withLinearHistory(1);
    Future<void> git(List<String> args) async {
      final r = await Process.run('git', args, workingDirectory: local.path);
      expect(r.exitCode, 0, reason: r.stderr.toString());
    }

    await git(['remote', 'add', 'origin', origin.path]);
    await git(['fetch', 'origin']);
    return (local, origin);
  }

  group('checkoutTrack', () {
    test('creates and checks out a local tracking branch', () async {
      final (local, origin) = await fixture();
      try {
        final sut = GitCliWriteOperations();
        final res = await sut.checkoutTrack(loc(local), 'origin/feature');
        expect(res, isA<GitSuccess<void>>());

        final head = await Process.run(
          'git',
          ['rev-parse', '--abbrev-ref', 'HEAD'],
          workingDirectory: local.path,
        );
        expect(head.stdout.toString().trim(), 'feature');

        final upstream = await Process.run(
          'git',
          ['rev-parse', '--abbrev-ref', 'feature@{upstream}'],
          workingDirectory: local.path,
        );
        expect(upstream.stdout.toString().trim(), 'origin/feature');
      } finally {
        await local.dispose();
        await origin.dispose();
      }
    });

    test('fails cleanly when the local branch already exists', () async {
      final (local, origin) = await fixture();
      try {
        final sut = GitCliWriteOperations();
        // local already has its own 'master' (withLinearHistory commits on it).
        final res = await sut.checkoutTrack(loc(local), 'origin/master');
        expect(res, isA<GitFailure<void>>());
      } finally {
        await local.dispose();
        await origin.dispose();
      }
    });
  });
}
```

- [ ] **Step 2: Run it — must fail to compile** (`checkoutTrack` undefined)

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/infrastructure/git/git_cli_write_operations_checkout_track_test.dart`
Expected: compilation error — `The method 'checkoutTrack' isn't defined`.

- [ ] **Step 3: Implement through the chain**

`lib/application/git/git_write_operations.dart` — after the `checkout` declaration:

```dart
  /// Creates and checks out a local branch tracking [remoteRef]
  /// (`git checkout --track <remoteRef>`). Git derives the local name by
  /// stripping the remote prefix; fails if that local branch already exists.
  Future<GitResult<void>> checkoutTrack(RepoLocation r, String remoteRef);
```

`lib/infrastructure/git/git_cli_ref_writer.dart` — after `checkout`:

```dart
  Future<GitResult<void>> checkoutTrack(RepoLocation r, String remoteRef) =>
      _git.runVoid(r, ['checkout', '--track', remoteRef]);
```

`lib/infrastructure/git/git_cli_write_operations.dart` — after the `checkout` override:

```dart
  @override
  Future<GitResult<void>> checkoutTrack(RepoLocation r, String remoteRef) =>
      _refs.checkoutTrack(r, remoteRef);
```

`lib/application/git/git_actions_service.dart` — after `checkout`:

```dart
  /// `git checkout --track <remoteRef>` — checks a remote branch out as a
  /// new local tracking branch.
  Future<ActionResult> checkoutTrack(RepoLocation repo, String remoteRef) =>
      _simple('Checkout', _write.checkoutTrack(repo, remoteRef));
```

`lib/ui/git/git_actions_controller.dart` — after `checkout`:

```dart
  /// `git checkout --track <remoteRef>` (remote branch → local branch).
  Future<ActionResult> checkoutTrack(
    BuildContext context,
    RepoLocation repo,
    String remoteRef,
  ) =>
      _runLocal(
        context,
        repo,
        () =>
            _ref.read(gitActionsServiceProvider).checkoutTrack(repo, remoteRef),
      );
```

- [ ] **Step 4: Add the service-mapping test**

In `test/application/git/git_actions_service_local_test.dart`, add to `_FakeWrite` (next to its `checkout` override):

```dart
  @override
  Future<GitResult<void>> checkoutTrack(RepoLocation r, String remoteRef) async =>
      voidResult;
```

and a test next to the other `_simple`-mapped ops (match the file's existing test style — it builds the service the same way as the surrounding tests):

```dart
  test('checkoutTrack failure surfaces a Checkout failed message', () async {
    final write = _FakeWrite()
      ..voidResult = const GitFailure<void>(GitErrorKind.unknown, 'boom');
    final result = await service(write).checkoutTrack(repo, 'origin/x');
    expect(result.outcome, ActionOutcome.failed);
    expect(result.message, 'Checkout failed: boom');
  });
```

(If `GitErrorKind.unknown` doesn't exist, use whichever `GitErrorKind` value the file's other failure tests use.)

- [ ] **Step 5: Run both test files — must pass**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/infrastructure/git/git_cli_write_operations_checkout_track_test.dart test/application/git/git_actions_service_local_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "fix(phase4): checkoutTrack op — remote branch as local tracking branch"
```

---

### Task 2: UI checkout flow — `checkoutRef` + `safeCheckout` via controller + all entry points

**Files:**
- Modify: `lib/ui/checkout/safe_checkout.dart` (full rewrite below)
- Modify: `lib/ui/sidebar/branch_tree_view.dart:65-71` (menu entry), `:116-118` (menu case), `:256-266` (double-tap)
- Modify: `lib/ui/sidebar/tag_row.dart:89-93`
- Modify: `lib/ui/commit_graph/commit_graph_panel.dart:360-370`
- Modify: `lib/ui/toolbar/branch_dropdown.dart:109-115`
- Test: `test/ui/checkout/local_branch_name_test.dart` (new)

- [ ] **Step 1: Write the failing name-derivation test**

Create `test/ui/checkout/local_branch_name_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/checkout/safe_checkout.dart';

void main() {
  test('localBranchNameFor strips exactly the remote segment', () {
    expect(localBranchNameFor('origin/main'), 'main');
    expect(localBranchNameFor('origin/feat/nested/x'), 'feat/nested/x');
    expect(localBranchNameFor('upstream/release/1.2'), 'release/1.2');
  });
}
```

- [ ] **Step 2: Run it — fails** (`localBranchNameFor` undefined)

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/checkout/local_branch_name_test.dart`
Expected: compilation error.

- [ ] **Step 3: Rewrite `lib/ui/checkout/safe_checkout.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/dialogs/checkout_changes_dialog.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';

/// `origin/feat/x` → `feat/x`. Git remote names cannot contain `/`, so
/// stripping the first path segment is always exactly the remote prefix.
String localBranchNameFor(String remoteBranchName) =>
    remoteBranchName.split('/').skip(1).join('/');

/// Checks out [name] — a local branch, tag, or remote branch — after handling
/// any uncommitted local changes. Remote branches ([isRemote] true) check out
/// as a local tracking branch: an existing local branch with the same short
/// name is reused, otherwise `git checkout --track` creates it.
///
/// Returns true on a successful checkout.
Future<bool> checkoutRef({
  required BuildContext context,
  required WidgetRef ref,
  required RepoLocation repo,
  required String name,
  bool isRemote = false,
}) async {
  var targetRef = name;
  var trackRemote = false;
  if (isRemote) {
    final localName = localBranchNameFor(name);
    final branches =
        await ref.read(gitReadOperationsProvider).getBranches(repo);
    final localExists =
        branches.any((b) => !b.isRemote && b.name == localName);
    if (localExists) {
      targetRef = localName;
    } else {
      trackRemote = true;
    }
  }
  if (!context.mounted) return false;
  return safeCheckout(
    context: context,
    ref: ref,
    repo: repo,
    targetRef: targetRef,
    trackRemote: trackRemote,
  );
}

/// Performs the checkout after handling any uncommitted local changes. If the
/// working tree is clean, checks out immediately; if dirty, prompts the user
/// to discard, stash, or keep the changes. The checkout itself goes through
/// [GitActionsController] so failures surface a snackbar and invalidation is
/// consistent with every other action. With [trackRemote], [targetRef] is a
/// remote ref checked out via `git checkout --track`.
///
/// Returns true on a successful checkout.
Future<bool> safeCheckout({
  required BuildContext context,
  required WidgetRef ref,
  required RepoLocation repo,
  required String targetRef,
  bool trackRemote = false,
}) async {
  final read = ref.read(gitReadOperationsProvider);
  final status = await read.getStatus(repo);
  final hasChanges = status.entries.any((e) =>
      e.workingTreeState != WorkingFileState.unmodified ||
      e.indexState != WorkingFileState.unmodified);

  CheckoutAction? action;
  if (hasChanges) {
    if (!context.mounted) return false;
    action = await CheckoutChangesDialog.show(context, targetRef);
    if (action == null) return false;
  }

  final controller = ref.read(gitActionsControllerProvider);

  switch (action) {
    case CheckoutAction.discard:
      final paths = status.entries.map((e) => e.path).toList();
      if (paths.isNotEmpty) {
        await ref.read(gitWriteOperationsProvider).discardChanges(repo, paths);
      }
    case CheckoutAction.stash:
      if (!context.mounted) return false;
      final stashRes = await controller.stashSave(
        context,
        repo,
        'Auto-stash before checkout to $targetRef',
        includeUntracked: true,
      );
      if (stashRes.outcome != ActionOutcome.success) return false;
    case CheckoutAction.keep:
    case null:
      break;
  }

  if (!context.mounted) return false;
  final result = trackRemote
      ? await controller.checkoutTrack(context, repo, targetRef)
      : await controller.checkout(context, repo, targetRef);
  return result.outcome == ActionOutcome.success;
}
```

(The old `_showError` helper, the `GitFailure` handling, the manual `ref.invalidate(gitReadOperationsProvider)` and the now-unused imports — `git_result.dart`, `app_palette.dart` — are gone: the controller owns error snackbars and invalidation.)

- [ ] **Step 4: Wire the entry points**

`lib/ui/sidebar/branch_tree_view.dart` — menu entry (lines 65-71): the remote case gets an explicit label:

```dart
    final entries = <AppContextMenuEntry<String>>[
      if (!isCurrent)
        AppMenuItem(
          value: 'checkout',
          label: isLocal ? 'Checkout' : 'Checkout as local branch',
          icon: Icons.swap_horiz,
        ),
```

menu case (lines 116-118):

```dart
      case 'checkout':
        final ok = await checkoutRef(
          context: context,
          ref: ref,
          repo: widget.repo,
          name: branchName,
          isRemote: branch.isRemote,
        );
        if (ok) _refresh();
```

double-tap (lines 256-266):

```dart
            onDoubleTap: branch == null || current
                ? null
                : () async {
                    final ok = await checkoutRef(
                      context: context,
                      ref: ref,
                      repo: widget.repo,
                      name: branch.name,
                      isRemote: branch.isRemote,
                    );
                    if (ok) _refresh();
                  },
```

`lib/ui/sidebar/tag_row.dart` — menu case (lines 89-93):

```dart
      case 'checkout':
        final ok = await safeCheckout(
          context: context,
          ref: ref,
          repo: repo,
          targetRef: tag.name,
        );
        if (ok) onRefresh();
```

`lib/ui/commit_graph/commit_graph_panel.dart` — ref-pill double-tap (lines 360-370):

```dart
                            onRefDoubleTap: (r) async {
                              final ok = await checkoutRef(
                                context: context,
                                ref: ref,
                                repo: widget.repo,
                                name: r.name,
                                isRemote: r.isRemote,
                              );
                              if (ok) {
                                ref.invalidate(_commitGraphDataProvider(repo));
                              }
                            },
```

`lib/ui/toolbar/branch_dropdown.dart` — `_switchBranch` tail (lines 109-115; add the `safe_checkout.dart` import):

```dart
    if (selected == null || !mounted) return;
    await safeCheckout(
      context: context,
      ref: ref,
      repo: repo,
      targetRef: selected,
    );
```

- [ ] **Step 5: Run targeted tests + analyze**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/checkout/local_branch_name_test.dart && & "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze`
Expected: test PASS; analyze clean (fix any unused-import leftovers it flags).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "fix(phase4): remote checkout creates tracking branch; safeCheckout at every entry point"
```

---

### Task 3: Annotated tags — `TagCreateDialog` + writer coverage

**Files:**
- Create: `lib/ui/dialogs/tag_create_dialog.dart`
- Modify: `lib/ui/commit_graph/commit_graph_panel.dart:607-615` (tag_here case)
- Test: `test/infrastructure/git/git_cli_write_operations_tag_test.dart` (add annotated test — the `-a -m` path has NO coverage today)
- Test: `test/ui/dialogs/tag_create_dialog_test.dart` (new)

- [ ] **Step 1: Write the failing annotated-tag infra test**

Add to the existing group in `test/infrastructure/git/git_cli_write_operations_tag_test.dart` (match its `loc`/fixture helpers — same shape as `git_cli_write_operations_branch_test.dart`):

```dart
    test('createTag with message creates an annotated tag', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        final sut = GitCliWriteOperations();
        final res = await sut.createTag(
          loc(f),
          'v9.9.9',
          message: 'release notes',
        );
        expect(res, isA<GitSuccess<void>>());
        final type = await Process.run(
          'git',
          ['cat-file', '-t', 'v9.9.9'],
          workingDirectory: f.path,
        );
        expect(type.stdout.toString().trim(), 'tag'); // not 'commit'
      } finally {
        await f.dispose();
      }
    });
```

- [ ] **Step 2: Run it**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/infrastructure/git/git_cli_write_operations_tag_test.dart`
Expected: PASS immediately (backend already implements `-a -m`) — this closes the coverage gap. If it fails, the writer is broken: stop and investigate before the UI work.

- [ ] **Step 3: Write the failing dialog widget test**

Create `test/ui/dialogs/tag_create_dialog_test.dart` (pump pattern from `test/ui/conflicts/merge_editor_dialog_test.dart` / `git_actions_controller_test.dart`):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/dialogs/tag_create_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  /// Pumps a host app whose button opens the dialog, assigning the dialog's
  /// result to the returned holder when it eventually closes.
  Future<List<TagCreateRequest?>> openDialog(WidgetTester tester) async {
    final resultHolder = <TagCreateRequest?>[null];
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [AppPalette.dark()]),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async =>
                resultHolder[0] = await TagCreateDialog.show(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(); // dialog is now open
    return resultHolder;
  }

  testWidgets('returns name + message for an annotated tag', (tester) async {
    final result = await openDialog(tester);
    await tester.enterText(find.byType(TextField).first, ' v1.0 ');
    await tester.enterText(find.byType(TextField).last, ' first release ');
    await tester.tap(find.text('Create tag'));
    await tester.pumpAndSettle(); // dialog closed → onPressed resumed
    expect(result[0]?.name, 'v1.0');
    expect(result[0]?.message, 'first release');
  });

  testWidgets('empty message yields a lightweight request', (tester) async {
    final result = await openDialog(tester);
    await tester.enterText(find.byType(TextField).first, 'v1.1');
    await tester.tap(find.text('Create tag'));
    await tester.pumpAndSettle();
    expect(result[0]?.name, 'v1.1');
    expect(result[0]?.message, isNull);
  });
}
```

- [ ] **Step 4: Run it — fails** (no `tag_create_dialog.dart`)

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/dialogs/tag_create_dialog_test.dart`
Expected: compilation error.

- [ ] **Step 5: Create `lib/ui/dialogs/tag_create_dialog.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// What the user asked for in [TagCreateDialog]: a tag [name] and an optional
/// annotation [message] — null means a lightweight tag.
final class TagCreateRequest {
  const TagCreateRequest(this.name, this.message);
  final String name;
  final String? message;
}

/// Prompts for a tag name plus an optional annotation message.
/// Returns null when cancelled (or confirmed with an empty name).
class TagCreateDialog {
  static Future<TagCreateRequest?> show(BuildContext context) async {
    final nameCtl = TextEditingController();
    final messageCtl = TextEditingController();
    final result = await showDialog<TagCreateRequest>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        TagCreateRequest? submit() {
          final name = nameCtl.text.trim();
          if (name.isEmpty) return null;
          final message = messageCtl.text.trim();
          return TagCreateRequest(name, message.isEmpty ? null : message);
        }

        return AppDialog(
          title: 'Tag here',
          width: 420,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtl,
                autofocus: true,
                style: TextStyle(color: palette.fg0, fontSize: 13),
                decoration: appInputDecoration(ctx, label: 'Tag name'),
                onSubmitted: (_) => Navigator.pop(ctx, submit()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageCtl,
                maxLines: 3,
                style: TextStyle(color: palette.fg0, fontSize: 13),
                decoration: appInputDecoration(
                  ctx,
                  label: 'Message (optional — creates an annotated tag)',
                ),
              ),
            ],
          ),
          actions: [
            AppButton.secondary(
              label: 'Cancel',
              onPressed: () => Navigator.pop(ctx),
            ),
            AppButton.primary(
              label: 'Create tag',
              onPressed: () => Navigator.pop(ctx, submit()),
            ),
          ],
        );
      },
    );
    nameCtl.dispose();
    messageCtl.dispose();
    return result;
  }
}
```

(`AppDialog`, `AppButton`, `appInputDecoration` all come from `app_dialog.dart`, same as `branch_tree_view.dart`'s `_promptText`. If `AppButton`'s parameter names differ, mirror `_promptText` exactly.)

- [ ] **Step 6: Wire `tag_here` in `lib/ui/commit_graph/commit_graph_panel.dart` (lines 607-615)**

```dart
      case 'tag_here':
        if (!context.mounted) return;
        final req = await TagCreateDialog.show(context);
        if (req == null) return;
        if (!context.mounted) return;
        await ref
            .read(gitActionsControllerProvider)
            .createTag(context, repo, req.name, at: sha, message: req.message);
```

Add `import 'package:gitopen/ui/dialogs/tag_create_dialog.dart';`. Keep `_promptText` — `branch_here` still uses it.

- [ ] **Step 7: Run tests + analyze**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/ui/dialogs/tag_create_dialog_test.dart test/infrastructure/git/git_cli_write_operations_tag_test.dart && & "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze`
Expected: PASS, analyze clean.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "fix(phase4): annotated tags from the UI (TagCreateDialog with optional message)"
```

---

### Task 4: `pushTag` + `fetchRemote` through the facade

**Files:**
- Modify: `lib/application/git/git_actions_service.dart` (after `push`, ~line 153)
- Modify: `lib/ui/git/git_actions_controller.dart` (after `push`, ~line 73)
- Modify: `lib/ui/sidebar/tag_row.dart:86,95-100`
- Modify: `lib/ui/sidebar/remotes_section.dart:193-196,242-261`
- Test: `test/application/git/git_actions_service_test.dart`

- [ ] **Step 1: Write the failing service tests**

In `test/application/git/git_actions_service_test.dart`, replace `_FakeWrite` with a version that also fakes `push` and records arguments:

```dart
/// Fake write op: `fetch`/`push` return the next queued stream per call
/// (initial, then retry), so a test can script "fail, then succeed".
/// Arguments are recorded so routing (remote/branch/tags) can be asserted.
class _FakeWrite implements GitWriteOperations {
  _FakeWrite(this._streams);
  final List<Stream<GitProgress> Function()> _streams;
  int calls = 0;
  String? lastFetchRemote;
  String? lastPushRemote;
  String? lastPushBranch;
  bool? lastPushTags;

  Stream<GitProgress> _next() {
    final s = _streams[calls < _streams.length ? calls : _streams.length - 1];
    calls++;
    return s();
  }

  @override
  Stream<GitProgress> fetch(
    RepoLocation r, {
    String? remote,
    bool all = false,
    AuthSpec? auth,
  }) {
    lastFetchRemote = remote;
    return _next();
  }

  @override
  Stream<GitProgress> push(
    RepoLocation r, {
    String? remote,
    String? branch,
    bool forceWithLease = false,
    bool pushTags = false,
    AuthSpec? auth,
  }) {
    lastPushRemote = remote;
    lastPushBranch = branch;
    lastPushTags = pushTags;
    return _next();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}
```

Add tests at the end of `main()`:

```dart
  test('pushTag pushes the single tag ref to the named remote', () async {
    final write = _FakeWrite([_ok]);
    final prompt = _FakePrompt(null);
    final progress = _FakeProgress();

    final result = await service(write)
        .pushTag(repo, 'v1.2.3', prompt: prompt, progress: progress);

    expect(result.outcome, ActionOutcome.success);
    expect(write.lastPushRemote, 'origin');
    expect(write.lastPushBranch, 'v1.2.3');
    expect(write.lastPushTags, isFalse); // the bug: --tags pushed everything
    expect(prompt.calls, 0);
  });

  test('fetchRemote fetches the named remote with auth-retry', () async {
    final write = _FakeWrite([() => _err('fatal: Authentication failed'), _ok]);
    final prompt = _FakePrompt(_chosen);
    final progress = _FakeProgress();

    final result = await service(write)
        .fetchRemote(repo, 'upstream', prompt: prompt, progress: progress);

    expect(result.outcome, ActionOutcome.success);
    expect(write.lastFetchRemote, 'upstream');
    expect(prompt.calls, 1);
    expect(write.calls, 2); // initial + retry
  });
```

- [ ] **Step 2: Run — fails** (`pushTag`/`fetchRemote` undefined)

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/application/git/git_actions_service_test.dart`
Expected: compilation error.

- [ ] **Step 3: Implement service methods** (`lib/application/git/git_actions_service.dart`, after `push`)

```dart
  /// `git push <remote> <tag>` — pushes exactly one tag ref, with progress +
  /// auth-retry.
  Future<ActionResult> pushTag(
    RepoLocation repo,
    String tagName, {
    String remote = 'origin',
    required AuthPrompt prompt,
    required ProgressSink progress,
  }) {
    return _runStream(
      OpKind.push,
      'Pushing tag $tagName',
      repo,
      (auth) => _write.push(repo, remote: remote, branch: tagName, auth: auth),
      prompt: prompt,
      progress: progress,
    );
  }

  /// `git fetch <remote>` with progress + auth-retry.
  Future<ActionResult> fetchRemote(
    RepoLocation repo,
    String remote, {
    required AuthPrompt prompt,
    required ProgressSink progress,
  }) {
    return _runStream(
      OpKind.fetch,
      'Fetching $remote',
      repo,
      (auth) => _write.fetch(repo, remote: remote, auth: auth),
      prompt: prompt,
      progress: progress,
    );
  }
```

- [ ] **Step 4: Run — passes**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/application/git/git_actions_service_test.dart`
Expected: PASS.

- [ ] **Step 5: Controller wrappers** (`lib/ui/git/git_actions_controller.dart`, after `push`)

```dart
  /// `git push <remote> <tag>` with progress + auth-retry.
  Future<ActionResult> pushTag(
    BuildContext context,
    RepoLocation repo,
    String tagName,
  ) {
    return _run(
      context,
      repo,
      (prompt, progress) => _ref
          .read(gitActionsServiceProvider)
          .pushTag(repo, tagName, prompt: prompt, progress: progress),
    );
  }

  /// `git fetch <remote>` with progress + auth-retry.
  Future<ActionResult> fetchRemote(
    BuildContext context,
    RepoLocation repo,
    String remoteName,
  ) {
    return _run(
      context,
      repo,
      (prompt, progress) => _ref
          .read(gitActionsServiceProvider)
          .fetchRemote(repo, remoteName, prompt: prompt, progress: progress),
    );
  }
```

- [ ] **Step 6: Switch the sidebar callsites**

`lib/ui/sidebar/tag_row.dart` — replace the `push_tag` case (95-100):

```dart
      case 'push_tag':
        await ref
            .read(gitActionsControllerProvider)
            .pushTag(context, repo, tag.name);
        onRefresh();
```

Delete the now-unused `final write = ref.read(gitWriteOperationsProvider);` (line 86) and, if nothing else uses it, the `application/providers.dart` import.

`lib/ui/sidebar/remotes_section.dart` — replace the `fetch` case (193-196):

```dart
      case 'fetch':
        await ref
            .read(gitActionsControllerProvider)
            .fetchRemote(context, repo, remote.name);
        onChanged();
```

Delete the whole `_fetchRemote` function (lines 242-261) and the imports it alone used (`running_operation.dart`; check `authResolverProvider`/`operationsProvider` usages before removing `providers.dart` — `write` is still used by edit_url/rename/remove). Add the `git_actions_controller.dart` import.

- [ ] **Step 7: Analyze + targeted tests**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze && & "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/application/git/git_actions_service_test.dart`
Expected: clean + PASS.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "fix(phase4): sidebar push-tag and per-remote fetch through the facade (auth-retry + progress)"
```

---

### Task 5: Flaky-test failure capture

**Files:**
- Create: `test/_helpers/flake_capture.dart`
- Modify: `test/infrastructure/git/git_cli_read_operations_commits_test.dart:26-37`
- Modify: `test/infrastructure/git/git_cli_read_operations_file_history_test.dart:60-70`

- [ ] **Step 1: Create `test/_helpers/flake_capture.dart`**

```dart
import 'dart:io';

/// Wraps a known-flaky real-git test [body]: when it throws, dumps the
/// fixture repo's git state — plus any [extraCommands] specific to the
/// assertion — to stderr before rethrowing. The two wrapped tests flake ONLY
/// under full-suite parallel load and the failure output has never been
/// captured; this makes every suite run a capture attempt (Phase 4 spec).
Future<void> withFlakeCapture(
  String repoPath,
  Future<void> Function() body, {
  List<List<String>> extraCommands = const [],
}) async {
  try {
    await body();
  } on Object catch (e) {
    stderr.writeln('=== FLAKE CAPTURED ($repoPath): $e');
    final commands = <List<String>>[
      ['log', '--oneline', '--all'],
      ['status', '--porcelain=v2'],
      ...extraCommands,
    ];
    for (final args in commands) {
      try {
        final r = await Process.run('git', args, workingDirectory: repoPath);
        stderr
          ..writeln('--- git ${args.join(' ')} (exit ${r.exitCode})')
          ..writeln(r.stdout)
          ..writeln(r.stderr);
      } on Object catch (runError) {
        stderr.writeln('--- git ${args.join(' ')} could not run: $runError');
      }
    }
    rethrow;
  }
}
```

- [ ] **Step 2: Wrap the skip/take test** (`git_cli_read_operations_commits_test.dart:26-37`; add `import '../../_helpers/flake_capture.dart';`)

```dart
    test('respects skip and take', () async {
      final f = await RepoFixture.withLinearHistory(10);
      try {
        await withFlakeCapture(
          f.path,
          extraCommands: const [
            ['log', '--skip=2', '--max-count=3', '--pretty=%H'],
          ],
          () async {
            final sut = GitCliReadOperations();
            final commits = await sut
                .getCommits(loc(f), const CommitQuery(skip: 2, take: 3))
                .toList();
            expect(
              commits,
              hasLength(3),
              reason: 'parsed: ${commits.map((c) => c.sha.value).toList()}',
            );
          },
        );
      } finally {
        await f.dispose();
      }
    });
```

(Note argument order: `withFlakeCapture(path, body, {extraCommands})` — written here with the named arg before the closure for readability; both orders compile.)

- [ ] **Step 3: Wrap the author test** (`git_cli_read_operations_file_history_test.dart:60-70`; same import). Keep the existing body verbatim inside the wrapper and pass:

```dart
          extraCommands: const [
            ['log', '--follow', '--pretty=%an <%ae>', '--', 'main.txt'],
          ],
```

- [ ] **Step 4: Run both files — pass (no flake expected single-file)**

Run: `& "C:\Users\g.chirico\flutter\bin\flutter.bat" test test/infrastructure/git/git_cli_read_operations_commits_test.dart test/infrastructure/git/git_cli_read_operations_file_history_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "test(phase4): capture git state when the two flaky fixture tests fail"
```

---

### Task 6: Finalize — version bump, full verification, PR

- [ ] **Step 1: Bump version in `pubspec.yaml`** — current `0.1.12` → `0.1.13` (CI's version-check requires a new unreleased version when `lib/` changes; verify the current value first).

- [ ] **Step 2: Format + full suite + analyze**

Run: `dart.bat format lib test && & "C:\Users\g.chirico\flutter\bin\flutter.bat" analyze && & "C:\Users\g.chirico\flutter\bin\flutter.bat" test`
Expected: no diffs beyond intended, analyze clean, all ~535 tests green.

- [ ] **Step 3: Commit + push + PR** (gh account: `gh auth switch --hostname github.com --user zN3utr4l`)

```bash
git add -A && git commit -m "chore(phase4): bump version to 0.1.13"
git push -u origin fix/phase4-s1-fixes
gh pr create --title "fix(phase4): S1 — remote checkout, annotated tags, safeCheckout everywhere, facade for push-tag/fetch" --body "..."
```

PR body summarizes the four fixes + instrumentation, links the Phase 4 spec, notes CD will release v0.1.13 on merge.
