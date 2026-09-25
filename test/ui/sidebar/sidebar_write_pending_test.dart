import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/refs/remote.dart';
import 'package:gitopen/domain/refs/stash.dart';
import 'package:gitopen/domain/refs/submodule.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/refs/worktree.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/sidebar/remotes_section.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/sidebar/submodule_row.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class _Read implements GitReadOperations {
  final reload = Completer<List<Remote>>();
  int remoteCalls = 0;
  int submoduleCalls = 0;
  final submoduleReload = Completer<List<Submodule>>();
  static const remote = Remote(
    name: 'origin',
    url: 'https://example.org/r',
    branches: [],
  );
  static final submodule = Submodule(
    path: 'vendor/lib',
    sha: CommitSha('aaaa'),
    status: SubmoduleStatus.uninitialized,
  );

  @override
  Future<List<Branch>> getLocalBranches(RepoLocation repo) async => [];
  @override
  Future<List<Branch>> getRemoteBranches(RepoLocation repo) async => [];
  @override
  Future<List<Tag>> getTags(RepoLocation repo) async => [];
  @override
  Future<List<Remote>> getRemotes(RepoLocation repo) {
    remoteCalls++;
    return remoteCalls == 1 ? Future.value([remote]) : reload.future;
  }

  @override
  Future<List<Stash>> getStashes(RepoLocation repo) async => [];
  @override
  Future<List<Submodule>> getSubmodules(RepoLocation repo) {
    submoduleCalls++;
    return submoduleCalls == 1
        ? Future.value([submodule])
        : submoduleReload.future;
  }

  @override
  Future<List<Worktree>> getWorktrees(RepoLocation repo) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Write implements GitWriteOperations {
  int removes = 0;
  int updates = 0;
  @override
  Future<GitResult<void>> removeRemote(RepoLocation repo, String name) async {
    removes++;
    return const GitSuccess<void>(null);
  }

  @override
  Future<GitResult<void>> updateSubmodule(
    RepoLocation repo,
    String path, {
    bool init = false,
    bool recursive = false,
  }) async {
    updates++;
    return const GitSuccess<void>(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  testWidgets(
    'remote remove stays pending through sidebar reload and rejects repeat',
    (tester) async {
      final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
      final read = _Read();
      final write = _Write();
      await tester.pumpWidget(
        _host(
          repo,
          read,
          write,
          RemoteGroup(remote: _Read.remote, repo: repo, onChanged: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('origin'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await tester.pump();
      expect(write.removes, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(RemoteGroup), findsOneWidget);
      expect(
        tester
            .widget<SidebarRowSurface>(find.byType(SidebarRowSurface))
            .onSecondaryTapDown,
        isNull,
      );
      await tester.tap(find.text('origin'), buttons: kSecondaryButton);
      await tester.pump();
      expect(write.removes, 1);
      read.reload.complete([]);
      read.submoduleReload.complete([_Read.submodule]);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('submodule update stays pending through sidebar reload', (
    tester,
  ) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
    final read = _Read();
    final write = _Write();
    await tester.pumpWidget(
      _host(
        repo,
        read,
        write,
        SubmoduleRow(submodule: _Read.submodule, repo: repo),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('vendor/lib'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Init & update'));
    await tester.pump();
    expect(write.updates, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<SidebarRowSurface>(find.byType(SidebarRowSurface))
          .onSecondaryTapDown,
      isNull,
    );
    await tester.tap(find.text('vendor/lib'), buttons: kSecondaryButton);
    await tester.pump();
    expect(write.updates, 1);
    read.reload.complete([_Read.remote]);
    read.submoduleReload.complete([_Read.submodule]);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

Widget _host(RepoLocation repo, _Read read, _Write write, Widget child) =>
    ProviderScope(
      overrides: [
        gitReadOperationsProvider.overrideWithValue(read),
        gitWriteOperationsProvider.overrideWithValue(write),
      ],
      child: MaterialApp(
        theme: ThemeData(
          extensions: [
            AppPalette.dark(),
            const AppSpacing.desktop(),
            const AppRadii.desktop(),
            const AppTypography.desktop(),
            const AppMotion.standard(),
          ],
        ),
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: Column(
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    ref.watch(sidebarDataProvider(repo));
                    return const SizedBox.shrink();
                  },
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
