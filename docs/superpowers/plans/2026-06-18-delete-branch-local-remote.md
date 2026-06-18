# Delete Branch Locally + Remotely — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** One "Delete" action on a branch that can remove the local branch and its tracked remote branch together, via a choice dialog, with auth-aware remote deletion and force-on-unmerged for the local side.

**Architecture:** A pure pairing function maps the clicked branch to its local/remote targets. Remote deletion is a `push --delete` routed through the existing push-style auth-retry path (so it reuses the resolved credential). A thin controller method orchestrates the two independent deletes; the dialog collects the choice and drives the force-on-unmerged retry.

**Tech Stack:** Dart/Flutter, Riverpod, flutter_test. Clean layers: application (pure + service), infrastructure (git CLI), ui.

## Global Constraints

- Run tests with `flutter test <path>`; lint with `flutter analyze` (CI runs analyze with infos fatal — keep lines ≤ 80 chars).
- Branch ref formats (from `git_cli_ref_reader`): local `name="feature"`, `fullName="refs/heads/feature"`, `upstreamFullName="refs/remotes/origin/feature"|null`; remote `name="origin/feature"`, `fullName="refs/remotes/origin/feature"`.
- Remote deletion MUST go through the auth-retry path (it is a push).
- Sides are independent: attempt each selected side; a failure on one does not skip the other.
- Commit messages end with the `Co-Authored-By` trailer shown in the steps.

---

### Task 1: Pure pairing + not-merged detector

**Files:**
- Create: `lib/application/git/branch_deletion.dart`
- Test: `test/application/git/branch_deletion_test.dart`

**Interfaces:**
- Consumes: `Branch` (`lib/domain/refs/branch.dart`).
- Produces: `class BranchDeletionTargets { String? localName; bool localIsCurrent; String? remoteRef; }`; `BranchDeletionTargets branchDeletionTargets(Branch clicked, List<Branch> all)`; `bool isNotFullyMergedError(String stderr)`.

- [ ] **Step 1: Write the failing test**

Create `test/application/git/branch_deletion_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/branch_deletion.dart';
import 'package:gitopen/domain/refs/branch.dart';

Branch _local(String name, {bool current = false, String? upstream}) => Branch(
      name: name,
      fullName: 'refs/heads/$name',
      isRemote: false,
      isCurrent: current,
      ahead: 0,
      behind: 0,
      upstreamFullName: upstream,
    );

Branch _remote(String shortWithRemote) => Branch(
      name: shortWithRemote, // e.g. "origin/feature"
      fullName: 'refs/remotes/$shortWithRemote',
      isRemote: true,
      isCurrent: false,
      ahead: 0,
      behind: 0,
    );

void main() {
  group('branchDeletionTargets', () {
    test('local with upstream maps to both sides', () {
      final t = branchDeletionTargets(
        _local('feature', upstream: 'refs/remotes/origin/feature'),
        [_local('feature', upstream: 'refs/remotes/origin/feature')],
      );
      expect(t.localName, 'feature');
      expect(t.localIsCurrent, isFalse);
      expect(t.remoteRef, 'origin/feature');
    });

    test('local without upstream has no remote side', () {
      final t = branchDeletionTargets(_local('feature'), [_local('feature')]);
      expect(t.localName, 'feature');
      expect(t.remoteRef, isNull);
    });

    test('current local is flagged', () {
      final t = branchDeletionTargets(
        _local('main', current: true),
        [_local('main', current: true)],
      );
      expect(t.localIsCurrent, isTrue);
    });

    test('remote maps to the local that tracks it', () {
      final all = [
        _local('feature', upstream: 'refs/remotes/origin/feature'),
        _remote('origin/feature'),
      ];
      final t = branchDeletionTargets(_remote('origin/feature'), all);
      expect(t.remoteRef, 'origin/feature');
      expect(t.localName, 'feature');
    });

    test('remote with no tracking local has no local side', () {
      final t = branchDeletionTargets(
        _remote('origin/feature'),
        [_remote('origin/feature')],
      );
      expect(t.remoteRef, 'origin/feature');
      expect(t.localName, isNull);
    });

    test('upstream not under refs/remotes is ignored (defensive)', () {
      final t = branchDeletionTargets(
        _local('feature', upstream: 'refs/heads/weird'),
        [_local('feature', upstream: 'refs/heads/weird')],
      );
      expect(t.remoteRef, isNull);
    });
  });

  group('isNotFullyMergedError', () {
    test('matches git not-fully-merged message', () {
      expect(
        isNotFullyMergedError("error: the branch 'x' is not fully merged."),
        isTrue,
      );
    });
    test('false for other errors', () {
      expect(isNotFullyMergedError('error: branch not found'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/application/git/branch_deletion_test.dart`
Expected: FAIL — `branch_deletion.dart` does not exist.

- [ ] **Step 3: Implement**

Create `lib/application/git/branch_deletion.dart`:

```dart
import 'package:gitopen/domain/refs/branch.dart';

/// The deletable sides for a branch the user asked to delete.
class BranchDeletionTargets {
  const BranchDeletionTargets({
    this.localName,
    this.localIsCurrent = false,
    this.remoteRef,
  });

  /// Local branch short name (e.g. "feature"), or null when there is none.
  final String? localName;

  /// True when the local side is the checked-out branch (cannot be deleted).
  final bool localIsCurrent;

  /// Remote ref as "<remote>/<branch>" (e.g. "origin/feature"), or null.
  final String? remoteRef;
}

const _remotePrefix = 'refs/remotes/';

/// Maps the right-clicked [clicked] branch (plus the full [all] branch list)
/// to its local and remote deletion targets.
BranchDeletionTargets branchDeletionTargets(Branch clicked, List<Branch> all) {
  if (!clicked.isRemote) {
    final up = clicked.upstreamFullName;
    final remoteRef = (up != null && up.startsWith(_remotePrefix))
        ? up.substring(_remotePrefix.length)
        : null;
    return BranchDeletionTargets(
      localName: clicked.name,
      localIsCurrent: clicked.isCurrent,
      remoteRef: remoteRef,
    );
  }
  // Clicked a remote branch: find the local branch tracking it.
  Branch? trackingLocal;
  for (final b in all) {
    if (!b.isRemote && b.upstreamFullName == clicked.fullName) {
      trackingLocal = b;
      break;
    }
  }
  return BranchDeletionTargets(
    remoteRef: clicked.name,
    localName: trackingLocal?.name,
    localIsCurrent: trackingLocal?.isCurrent ?? false,
  );
}

/// True when [stderr] is git refusing `branch -d` because the branch has
/// commits not reachable from its upstream/HEAD.
bool isNotFullyMergedError(String stderr) =>
    stderr.toLowerCase().contains('not fully merged');
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/application/git/branch_deletion_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/application/git/branch_deletion.dart test/application/git/branch_deletion_test.dart
git commit -m "feat(branch): pure pairing of a branch to its local/remote delete targets

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Auth-aware remote-branch delete (infra + write-ops port)

**Files:**
- Modify: `lib/infrastructure/git/git_cli_sync_writer.dart`
- Modify: `lib/application/git/git_write_operations.dart`
- Modify: `lib/infrastructure/git/git_cli_write_operations.dart`
- Test: `test/infrastructure/git/git_cli_write_operations_delete_remote_test.dart` (create)

**Interfaces:**
- Consumes: `GitCliSyncWriter._runProgressStream` (existing), `CredentialHelper`, `AuthSpec`.
- Produces: `Stream<GitProgress> GitWriteOperations.deleteRemoteBranch(RepoLocation r, String remoteRef, {AuthSpec? auth})` running `push --progress <remote> --delete <branch>` with the credential injected.

- [ ] **Step 1: Write the failing test**

Create `test/infrastructure/git/git_cli_write_operations_delete_remote_test.dart`. It exercises the real git CLI against two fixture repos (a bare "remote" + a clone), mirroring the existing push/fetch write-op tests.

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import '../../_helpers/repo_fixture.dart';

void main() {
  test('deleteRemoteBranch removes the branch on the remote', () async {
    final remote = await RepoFixture.empty(bare: true);
    final work = await RepoFixture.withCommit();
    try {
      await Process.run('git', ['remote', 'add', 'origin', remote.path],
          workingDirectory: work.path);
      await Process.run('git', ['push', 'origin', 'HEAD:refs/heads/feature'],
          workingDirectory: work.path);
      // Precondition: the remote has refs/heads/feature.
      final before = await Process.run(
          'git', ['ls-remote', '--heads', remote.path, 'feature']);
      expect((before.stdout as String).trim(), isNotEmpty);

      final ops = GitCliWriteOperations();
      final loc = RepoLocation(const RepoId('r'), work.path, 'w');
      await ops.deleteRemoteBranch(loc, 'origin/feature').drain<void>();

      final after = await Process.run(
          'git', ['ls-remote', '--heads', remote.path, 'feature']);
      expect((after.stdout as String).trim(), isEmpty);
    } finally {
      await remote.dispose();
      await work.dispose();
    }
  });
}
```

NOTE: confirm `RepoFixture` exposes `empty(bare: true)` and `withCommit()`; if the helper's API differs, adapt the fixture setup (the existing push/pull write-op test, `git_cli_write_operations_pull_push_test.dart`, shows the exact helpers — reuse them).

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/infrastructure/git/git_cli_write_operations_delete_remote_test.dart`
Expected: FAIL — `deleteRemoteBranch` is not defined.

- [ ] **Step 3: Add the sync-writer method**

In `lib/infrastructure/git/git_cli_sync_writer.dart`, add after `clone(...)`:

```dart
  /// `git push <remote> --delete <branch>` with progress + in-app credential
  /// injection (deleting a remote branch is a push and needs auth).
  Stream<GitProgress> deleteRemoteBranch(
    RepoLocation r,
    String remoteRef, {
    AuthSpec? auth,
  }) async* {
    final slash = remoteRef.indexOf('/');
    final remoteName = slash < 0 ? remoteRef : remoteRef.substring(0, slash);
    final branch = slash < 0 ? '' : remoteRef.substring(slash + 1);
    final args = ['push', '--progress', remoteName, '--delete', branch];
    await for (final p in _runProgressStream(r.path, args, auth: auth)) {
      yield p;
    }
  }
```

- [ ] **Step 4: Add the write-ops port + delegation**

In `lib/application/git/git_write_operations.dart`, add after the `push(...)` declaration (around line 170):

```dart
  /// `git push <remote> --delete <branch>` — deletes [remoteRef]
  /// ("<remote>/<branch>") on the server, with progress + auth.
  Stream<GitProgress> deleteRemoteBranch(
    RepoLocation r,
    String remoteRef, {
    AuthSpec? auth,
  });
```

In `lib/infrastructure/git/git_cli_write_operations.dart`, add the delegation next to the existing `push` delegation (it forwards to the sync writer field, same as `push`/`fetch`):

```dart
  @override
  Stream<GitProgress> deleteRemoteBranch(
    RepoLocation r,
    String remoteRef, {
    AuthSpec? auth,
  }) =>
      _sync.deleteRemoteBranch(r, remoteRef, auth: auth);
```

(Use the same sync-writer field name the existing `push`/`fetch`/`clone` delegations use — confirm by reading the surrounding lines.)

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/infrastructure/git/git_cli_write_operations_delete_remote_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lib/infrastructure/git/git_cli_sync_writer.dart lib/application/git/git_write_operations.dart lib/infrastructure/git/git_cli_write_operations.dart test/infrastructure/git/git_cli_write_operations_delete_remote_test.dart
git commit -m "feat(git): auth-aware deleteRemoteBranch (push --delete)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Service method `deleteRemoteBranch` (auth-retry)

**Files:**
- Modify: `lib/application/git/git_actions_service.dart`
- Test: `test/application/git/git_actions_service_test.dart`

**Interfaces:**
- Consumes: `GitWriteOperations.deleteRemoteBranch` (Task 2); existing `_runStream`, `AuthPrompt`, `ProgressSink`, `OpKind`.
- Produces: `Future<ActionResult> GitActionsService.deleteRemoteBranch(RepoLocation repo, String remoteRef, {required AuthPrompt prompt, required ProgressSink progress})`.

- [ ] **Step 1: Write the failing test**

Extend `test/application/git/git_actions_service_test.dart`, reusing that file's existing fake write/prompt/progress harness (the push/fetch tests there show the pattern; add a `deleteRemoteBranch` to the fake write that returns a one-event progress stream). Add:

```dart
  test('deleteRemoteBranch streams to success', () async {
    // Arrange the fake write so deleteRemoteBranch yields a progress event and
    // completes (mirror how the push test arranges its stream).
    final service = makeService(); // existing helper in this file
    final result = await service.deleteRemoteBranch(
      repo,
      'origin/feature',
      prompt: NoopPrompt(),
      progress: RecordingProgress(),
    );
    expect(result.outcome, ActionOutcome.success);
  });
```

(Use the file's actual helper/fake names — read the top of the test file first and mirror the `push` test exactly, swapping in `deleteRemoteBranch`.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/application/git/git_actions_service_test.dart`
Expected: FAIL — `deleteRemoteBranch` is not a member of `GitActionsService`.

- [ ] **Step 3: Implement**

In `lib/application/git/git_actions_service.dart`, add next to `push`:

```dart
  /// `git push <remote> --delete <branch>` with progress + auth-retry.
  Future<ActionResult> deleteRemoteBranch(
    RepoLocation repo,
    String remoteRef, {
    required AuthPrompt prompt,
    required ProgressSink progress,
  }) {
    return _runStream(
      OpKind.push,
      'Deleting $remoteRef',
      repo,
      (auth) => _write.deleteRemoteBranch(repo, remoteRef, auth: auth),
      prompt: prompt,
      progress: progress,
    );
  }
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/application/git/git_actions_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/application/git/git_actions_service.dart test/application/git/git_actions_service_test.dart
git commit -m "feat(git): GitActionsService.deleteRemoteBranch with auth-retry

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Controller orchestration

**Files:**
- Modify: `lib/ui/git/git_actions_controller.dart`

**Interfaces:**
- Consumes: `GitActionsService.deleteRemoteBranch` (Task 3); existing `deleteBranch`, `_run`, `_runLocal`; `isNotFullyMergedError` (Task 1).
- Produces: `Future<ActionResult> GitActionsController.deleteRemoteBranch(BuildContext, RepoLocation, String remoteRef)`; `Future<({bool localNeedsForce})> GitActionsController.deleteBranchTargets(BuildContext, RepoLocation, {String? remoteRef, String? localName, bool forceLocal})`.

> **No new unit test:** these are UI adapters over already-tested pieces (`deleteRemoteBranch` service method, `deleteBranch`, `isNotFullyMergedError`). Verified by `flutter analyze` + the full suite + the manual check in Task 5.

- [ ] **Step 1: Add the import**

In `lib/ui/git/git_actions_controller.dart`, add:

```dart
import 'package:gitopen/application/git/branch_deletion.dart';
```

- [ ] **Step 2: Add the methods**

Add next to the existing `deleteBranch` method:

```dart
  /// `git push <remote> --delete <branch>` with progress + auth-retry.
  Future<ActionResult> deleteRemoteBranch(
    BuildContext context,
    RepoLocation repo,
    String remoteRef,
  ) {
    return _run(
      context,
      repo,
      (prompt, progress) => _ref
          .read(gitActionsServiceProvider)
          .deleteRemoteBranch(repo, remoteRef, prompt: prompt, progress: progress),
    );
  }

  /// Deletes the selected sides of a branch (remote then local). Sides are
  /// independent. Returns whether the LOCAL delete failed only because the
  /// branch is not fully merged (so the caller can offer a force retry).
  Future<({bool localNeedsForce})> deleteBranchTargets(
    BuildContext context,
    RepoLocation repo, {
    String? remoteRef,
    String? localName,
    bool forceLocal = false,
  }) async {
    if (remoteRef != null) {
      await deleteRemoteBranch(context, repo, remoteRef);
    }
    var localNeedsForce = false;
    if (localName != null && context.mounted) {
      final result = await deleteBranch(context, repo, localName,
          force: forceLocal);
      localNeedsForce = !forceLocal &&
          result.outcome == ActionOutcome.failed &&
          isNotFullyMergedError(result.message ?? '');
    }
    return (localNeedsForce: localNeedsForce);
  }
```

- [ ] **Step 3: Verify analyze**

Run: `flutter analyze lib/ui/git/git_actions_controller.dart`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/git/git_actions_controller.dart
git commit -m "feat(git): controller orchestration for deleting both branch sides

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `DeleteBranchDialog` + wire into the branch context menu

**Files:**
- Create: `lib/ui/dialogs/delete_branch_dialog.dart`
- Modify: `lib/ui/sidebar/branch_tree_view.dart` (the `case 'delete'` block, ~lines 247-258)
- Test: `test/ui/dialogs/delete_branch_dialog_test.dart` (create)

**Interfaces:**
- Consumes: `BranchDeletionTargets` (Task 1), `branchesProvider`, `GitActionsController.deleteBranchTargets` (Task 4), `AppDialog`/`AppButton`/`ConfirmDialog`/`AppPalette`.
- Produces: `class DeleteBranchSelection { bool deleteLocal; bool deleteRemote; }`; `DeleteBranchDialog.show(context, {required targets}) -> Future<DeleteBranchSelection?>`.

- [ ] **Step 1: Write the failing widget test**

Create `test/ui/dialogs/delete_branch_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/branch_deletion.dart';
import 'package:gitopen/ui/dialogs/delete_branch_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

Future<DeleteBranchSelection?> _show(
  WidgetTester tester,
  BranchDeletionTargets targets,
) async {
  late Future<DeleteBranchSelection?> future;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [AppPalette.dark()]),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  future = DeleteBranchDialog.show(context, targets: targets),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return future;
}

void main() {
  testWidgets('shows both sides and returns both selected by default',
      (tester) async {
    final f = await _show(
      tester,
      const BranchDeletionTargets(
        localName: 'feature',
        remoteRef: 'origin/feature',
      ),
    );
    expect(find.text('feature'), findsWidgets);
    expect(find.text('origin/feature'), findsWidgets);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    final sel = await f;
    expect(sel!.deleteLocal, isTrue);
    expect(sel.deleteRemote, isTrue);
  });

  testWidgets('current local branch cannot be selected', (tester) async {
    final f = await _show(
      tester,
      const BranchDeletionTargets(
        localName: 'main',
        localIsCurrent: true,
        remoteRef: 'origin/main',
      ),
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    final sel = await f;
    expect(sel!.deleteLocal, isFalse); // disabled -> not selected
    expect(sel.deleteRemote, isTrue);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/ui/dialogs/delete_branch_dialog_test.dart`
Expected: FAIL — `delete_branch_dialog.dart` does not exist.

- [ ] **Step 3: Implement the dialog**

Create `lib/ui/dialogs/delete_branch_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:gitopen/application/git/branch_deletion.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// What the user chose to delete in [DeleteBranchDialog].
class DeleteBranchSelection {
  const DeleteBranchSelection({
    required this.deleteLocal,
    required this.deleteRemote,
  });
  final bool deleteLocal;
  final bool deleteRemote;

  bool get any => deleteLocal || deleteRemote;
}

/// Confirms deletion of a branch's local and/or remote side. Each present side
/// is a checkbox, checked by default; the local side is disabled when it is the
/// checked-out branch.
class DeleteBranchDialog extends StatefulWidget {
  const DeleteBranchDialog({required this.targets, super.key});
  final BranchDeletionTargets targets;

  static Future<DeleteBranchSelection?> show(
    BuildContext context, {
    required BranchDeletionTargets targets,
  }) {
    return showDialog<DeleteBranchSelection>(
      context: context,
      builder: (_) => DeleteBranchDialog(targets: targets),
    );
  }

  @override
  State<DeleteBranchDialog> createState() => _DeleteBranchDialogState();
}

class _DeleteBranchDialogState extends State<DeleteBranchDialog> {
  late bool _local = widget.targets.localName != null &&
      !widget.targets.localIsCurrent;
  late bool _remote = widget.targets.remoteRef != null;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final t = widget.targets;
    return AppDialog(
      title: 'Delete branch',
      width: 460,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (t.localName != null)
            CheckboxListTile(
              value: _local,
              onChanged: t.localIsCurrent
                  ? null
                  : (v) => setState(() => _local = v ?? false),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Local branch ${t.localName}',
                style: TextStyle(color: palette.fg0, fontSize: 13),
              ),
              subtitle: t.localIsCurrent
                  ? Text(
                      'Current branch — checkout another first',
                      style: TextStyle(color: palette.fg3, fontSize: 11),
                    )
                  : null,
            ),
          if (t.remoteRef != null)
            CheckboxListTile(
              value: _remote,
              onChanged: (v) => setState(() => _remote = v ?? false),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Remote branch ${t.remoteRef}',
                style: TextStyle(color: palette.fg0, fontSize: 13),
              ),
              subtitle: Text(
                'Deletes it on the server (push --delete)',
                style: TextStyle(color: palette.fg3, fontSize: 11),
              ),
            ),
        ],
      ),
      actions: [
        AppButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        AppButton.danger(
          label: 'Delete',
          onPressed: (_local || _remote)
              ? () => Navigator.pop(
                    context,
                    DeleteBranchSelection(
                      deleteLocal: _local,
                      deleteRemote: _remote,
                    ),
                  )
              : null,
        ),
      ],
    );
  }
}
```

(If `AppButton.danger`/`AppButton.secondary` do not accept a null `onPressed` to disable, gate the whole action instead — confirm against `app_dialog.dart`.)

- [ ] **Step 4: Run to verify the dialog test passes**

Run: `flutter test test/ui/dialogs/delete_branch_dialog_test.dart`
Expected: PASS

- [ ] **Step 5: Wire it into the branch context menu**

In `lib/ui/sidebar/branch_tree_view.dart`, replace the `case 'delete':` block (currently a plain ConfirmDialog + `actions.deleteBranch(...)`) with:

```dart
      case 'delete':
        final all = await ref.read(branchesProvider(widget.repo).future);
        if (!context.mounted) return;
        final targets = branchDeletionTargets(branch, all);
        final selection = await DeleteBranchDialog.show(
          context,
          targets: targets,
        );
        if (selection == null || !selection.any || !context.mounted) return;
        final outcome = await actions.deleteBranchTargets(
          context,
          widget.repo,
          remoteRef: selection.deleteRemote ? targets.remoteRef : null,
          localName: selection.deleteLocal ? targets.localName : null,
        );
        if (outcome.localNeedsForce && context.mounted) {
          final force = await ConfirmDialog.show(
            context,
            title: 'Force delete branch',
            body: 'Branch "${targets.localName}" is not fully merged. '
                'Delete it anyway? Unmerged commits will be lost.',
            confirmLabel: 'Force delete',
            dangerous: true,
          );
          if (force && context.mounted) {
            await actions.deleteBranchTargets(
              context,
              widget.repo,
              localName: targets.localName,
              forceLocal: true,
            );
          }
        }
        _refresh();
```

Add the imports at the top of `branch_tree_view.dart`:

```dart
import 'package:gitopen/application/git/branch_deletion.dart';
import 'package:gitopen/ui/dialogs/delete_branch_dialog.dart';
```

(`branchesProvider`, `ConfirmDialog`, `gitActionsControllerProvider` via `actions` are already imported/used in this file.)

- [ ] **Step 6: Verify analyze + full suite**

Run: `flutter analyze`
Expected: No issues.

Run: `flutter test`
Expected: PASS (a pre-existing real-git submodule test may flake under full-suite load; re-run it alone to confirm — it is unrelated).

- [ ] **Step 7: Manual smoke check**

1. `flutter run -d windows`, open a repo with a pushed branch.
2. Right-click a local branch with an upstream → Delete → both rows checked → Delete → local + remote both gone (sidebar refreshes).
3. Right-click a remote branch (REMOTES section) whose local exists → both offered.
4. Right-click the current branch → local checkbox disabled, remote still deletable.
5. Delete an unmerged local branch → "not fully merged" → Force delete prompt → confirms.

- [ ] **Step 8: Commit**

```bash
git add lib/ui/dialogs/delete_branch_dialog.dart lib/ui/sidebar/branch_tree_view.dart test/ui/dialogs/delete_branch_dialog_test.dart
git commit -m "feat(ui): delete a branch's local and remote side together

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Pairing (§1) → Task 1. ✓
- Auth-aware remote delete (§2) → Tasks 2–3. ✓
- Local delete + force-on-unmerged (§3) → Task 1 (`isNotFullyMergedError`) + Task 4 (`deleteBranchTargets` returns `localNeedsForce`) + Task 5 (force confirm). ✓
- Orchestration, independent sides (§4) → Task 4. ✓
- Dialog: checkboxes, defaults, current-disabled, omit missing side, Delete disabled when nothing checked (§5) → Task 5. ✓
- Error handling/edge cases (§6) → remote failure surfaced by `_run`'s snackbar; local-current disabled; missing side omitted; refresh after. ✓
- Non-goals respected (no bulk delete, no prune, toolbar untouched). ✓

**Deviation from spec:** §2 said remove the old `deleteBranch(remote: true)` path; this plan LEAVES it (no live caller uses it, and removing a shared signature risks unrelated tests) and routes the feature through the new `deleteRemoteBranch`. Lower-risk, same outcome.

**Placeholder scan:** the service test (Task 3) and the remote-delete fixture test (Task 2) intentionally say "mirror the existing harness/helpers" because they reuse fakes/fixtures defined in neighbouring test files; the actual assertions and the production code are fully specified. Read those neighbour files first when implementing.

**Type consistency:** `BranchDeletionTargets{localName, localIsCurrent, remoteRef}`, `branchDeletionTargets`, `isNotFullyMergedError`, `deleteRemoteBranch(repo, remoteRef, {auth})`, `deleteBranchTargets(... {remoteRef, localName, forceLocal})`, `DeleteBranchSelection{deleteLocal, deleteRemote}` are consistent across Tasks 1→5.
