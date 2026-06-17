import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/workspaces/repository_registry.dart';
import 'package:gitopen/application/workspaces/workspace_manager.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/refs/remote.dart';
import 'package:gitopen/domain/refs/stash.dart';
import 'package:gitopen/domain/refs/submodule.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/refs/worktree.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/sidebar/sidebar.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Returns branches on the first load; the second load (the refresh) hangs
/// until [release], so the sidebar provider sits in its reloading state.
class _ReloadFake implements GitReadOperations {
  static const _branch = Branch(
    name: 'master',
    fullName: 'refs/heads/master',
    isRemote: false,
    isCurrent: true,
    ahead: 0,
    behind: 0,
  );

  int _localCalls = 0;
  final Completer<List<Branch>> _hang = Completer<List<Branch>>();

  void release() => _hang.complete(const [_branch]);

  @override
  Future<List<Branch>> getLocalBranches(RepoLocation repo) async {
    _localCalls++;
    return _localCalls == 1 ? const [_branch] : _hang.future;
  }

  @override
  Future<List<Branch>> getRemoteBranches(RepoLocation repo) async => const [];
  @override
  Future<List<Branch>> getBranches(RepoLocation repo) async => const [_branch];
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
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

class _FakeRegistry implements RepositoryRegistry {
  _FakeRegistry(this._repo);
  final RepoLocation _repo;

  @override
  Future<RepoLocation> add(String path) async => _repo;

  @override
  Future<void> touchLastOpened(RepoId id) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

void main() {
  testWidgets('sidebar keeps branches visible during a refresh',
      (tester) async {
    final fake = _ReloadFake();
    const repo = RepoLocation(RepoId('r'), '/r', 't');

    final container = ProviderContainer(
      overrides: [
        gitReadOperationsProvider.overrideWithValue(fake),
        activeWorkspaceIdProvider.overrideWith((ref) => repo.id),
        workspaceManagerProvider.overrideWith(
          (ref) => WorkspaceManager(_FakeRegistry(repo)),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(workspaceManagerProvider.notifier).open('/r');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: const Scaffold(body: Sidebar()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('master'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // Simulate the auto-refresh (fetch / focus regain) invalidating the git
    // read layer; the sidebar provider reloads and its second load hangs.
    container.invalidate(gitReadOperationsProvider);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // The previous branches must stay on screen — no full-panel spinner.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('master'), findsOneWidget);

    fake.release();
    await tester.pumpAndSettle();
  });
}
