import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/refs/remote.dart';
import 'package:gitopen/domain/refs/stash.dart';
import 'package:gitopen/domain/refs/submodule.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/refs/worktree.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/operations/blocking_overlay.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

import '../../_helpers/operations.dart';

const _branch = Branch(
  name: 'feature',
  fullName: 'refs/heads/feature',
  isRemote: false,
  isCurrent: false,
  ahead: 0,
  behind: 0,
);

/// The sidebar's branch list reloads only when [release] is called, so the
/// test can hold the tree "still reloading" after `git branch -d` returned.
class _SidebarRead implements GitReadOperations {
  int localCalls = 0;
  final _reload = Completer<List<Branch>>();

  void release() => _reload.complete(const []);

  @override
  Future<List<Branch>> getLocalBranches(RepoLocation repo) {
    localCalls++;
    return localCalls == 1
        ? Future.value(const [_branch])
        : _reload.future;
  }

  @override
  Future<List<Branch>> getRemoteBranches(RepoLocation repo) async => const [];
  @override
  Future<List<Tag>> getTags(RepoLocation repo) async => const [];
  @override
  Future<List<Remote>> getRemotes(RepoLocation repo) async => const [];
  @override
  Future<List<Stash>> getStashes(RepoLocation repo) async => const [];
  @override
  Future<List<Submodule>> getSubmodules(RepoLocation repo) async => const [];
  @override
  Future<List<Worktree>> getWorktrees(RepoLocation repo) async => const [];
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not faked');
}

class _DeleteWrite implements GitWriteOperations {
  int deletes = 0;

  @override
  Future<GitResult<void>> deleteBranch(
    RepoLocation repo,
    String name, {
    bool force = false,
    bool remote = false,
  }) async {
    deletes++;
    return const GitSuccess<void>(null);
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not faked');
}

void main() {
  testWidgets('branch delete stays pending until the sidebar reloads',
      (tester) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'test');
    final read = _SidebarRead();
    final write = _DeleteWrite();
    final container = ProviderContainer(
      overrides: [
        gitReadOperationsProvider.overrideWithValue(read),
        operationsProvider.overrideWith(
          (ref) => OperationsNotifier(InMemoryActivityLog()),
        ),
        gitActionsServiceProvider.overrideWithValue(
          GitActionsService(
            write: write,
            resolveProfile: (_) async => null,
            errorText: (e) => e.toString(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: Stack(
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final data = ref.watch(sidebarDataProvider(repo));
                    return Column(
                      children: [
                        Text('branches:${data.value?.branches.length}'),
                        ElevatedButton(
                          onPressed: () => ref
                              .read(gitActionsControllerProvider)
                              .deleteBranchTargets(
                                context,
                                repo,
                                localName: 'feature',
                              ),
                          child: const Text('delete'),
                        ),
                      ],
                    );
                  },
                ),
                const BlockingOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('branches:1'), findsOneWidget);

    await tester.tap(find.text('delete'));
    // Past the anti-flicker delay: git has returned, the sidebar has not.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(write.deletes, 1);
    expect(read.localCalls, 2, reason: 'the sidebar is reloading');
    expect(find.text('Deleting branch feature…'), findsOneWidget);
    expect(find.text('branches:1'), findsOneWidget, reason: 'stale list still');

    read.release();
    await tester.pump();
    await tester.pump();
    expect(container.read(busyProvider).isBusy, isFalse);
    expect(find.text('branches:0'), findsOneWidget);
    // Let the minimum-visible window expire.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Deleting branch feature…'), findsNothing);
  });
}
