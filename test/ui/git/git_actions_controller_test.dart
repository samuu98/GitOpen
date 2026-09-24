import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/application/git/stash_safety_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/ui/git/git_actions_controller.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

class _StashSafetyFake implements StashSafetyOperations {
  int preserveCalls = 0;
  bool? pop;

  @override
  Future<GitResult<List<String>>> overlap(RepoLocation repo, int index) async =>
      const GitSuccess(['same file.txt', 'other.txt']);

  @override
  Future<GitResult<StashRestoreResult>> applyPreservingLocal(
    RepoLocation repo,
    int index, {
    required bool pop,
  }) async {
    preserveCalls++;
    this.pop = pop;
    return const GitSuccess(StashRestoreResult());
  }
}

/// Fake write whose `merge` returns a canned result, so the controller's
/// snackbar/feedback behaviour can be driven without git.
class _FakeWrite implements GitWriteOperations {
  GitResult<MergeOutcome> mergeResult = const GitSuccess<MergeOutcome>(
    MergeUpToDate(),
  );
  final checkoutCompleter = Completer<GitResult<void>>();
  String? checkoutRef;

  @override
  Future<GitResult<void>> checkout(
    RepoLocation r,
    String ref, {
    bool force = false,
  }) {
    checkoutRef = ref;
    return checkoutCompleter.future;
  }

  @override
  Future<GitResult<MergeOutcome>> merge(
    RepoLocation r,
    String ref, {
    MergeStrategy strategy = MergeStrategy.defaultStrategy,
  }) async => mergeResult;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

class _StatusFake implements GitReadOperations {
  final statusCompleter = Completer<RepoStatus>();
  int statusCalls = 0;

  @override
  Future<RepoStatus> getStatus(RepoLocation repo) {
    statusCalls++;
    return statusCompleter.future;
  }

  @override
  Future<List<Branch>> getLocalBranches(RepoLocation repo) async {
    return const [
      Branch(
        name: 'feature',
        fullName: 'refs/heads/feature',
        isRemote: false,
        isCurrent: true,
        ahead: 0,
        behind: 0,
      ),
    ];
  }

  @override
  Future<List<Branch>> getRemoteBranches(RepoLocation repo) async {
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

RepoStatus _statusOn(String branch) => RepoStatus(
  currentBranch: branch,
  isDetached: false,
  isBare: false,
  entries: const [],
);

void main() {
  final repo = RepoLocation(RepoId.newId(), 'unused', 'test');

  GitActionsService service(_FakeWrite write) => GitActionsService(
    write: write,
    resolveProfile: (_) async => null,
    errorText: (e) => e.toString(),
  );

  Widget host(GitActionsService svc) {
    return ProviderScope(
      overrides: [gitActionsServiceProvider.overrideWithValue(svc)],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => Center(
              child: ElevatedButton(
                onPressed: () => ref
                    .read(gitActionsControllerProvider)
                    .merge(
                      context,
                      repo,
                      'feature',
                      MergeStrategy.defaultStrategy,
                    ),
                child: const Text('merge'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('merge conflict surfaces a conflict snackbar', (tester) async {
    final write = _FakeWrite()
      ..mergeResult = const GitSuccess<MergeOutcome>(
        MergeConflict(['a.txt', 'b.txt']),
      );
    await tester.pumpWidget(host(service(write)));
    await tester.tap(find.text('merge'));
    await tester.pump(); // run the tap handler / start the future
    await tester.pump(const Duration(milliseconds: 50)); // complete + snackbar

    expect(find.textContaining('Merge conflict in 2 file(s)'), findsOneWidget);
  });

  testWidgets('merge success shows no snackbar', (tester) async {
    final write = _FakeWrite()
      ..mergeResult = const GitSuccess<MergeOutcome>(MergeUpToDate());
    await tester.pumpWidget(host(service(write)));
    await tester.tap(find.text('merge'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('checkout stays busy until refreshed status is available', (
    tester,
  ) async {
    final write = _FakeWrite();
    final read = _StatusFake();
    final container = ProviderContainer(
      overrides: [
        gitActionsServiceProvider.overrideWithValue(service(write)),
        gitReadOperationsProvider.overrideWithValue(read),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => ref
                    .read(gitActionsControllerProvider)
                    .checkout(context, repo, 'feature'),
                child: const Text('checkout'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('checkout'));
    await tester.pump();
    expect(write.checkoutRef, 'feature');
    expect(container.read(busyProvider).isBusy, isTrue);
    expect(container.read(busyProvider).label, 'Checking out feature…');

    write.checkoutCompleter.complete(const GitSuccess<void>(null));
    await tester.pump();

    expect(read.statusCalls, 1);
    expect(container.read(busyProvider).isBusy, isTrue);

    read.statusCompleter.complete(_statusOn('feature'));
    await tester.pump();
    await tester.pump();

    expect(container.read(busyProvider).isBusy, isFalse);
  });

  testWidgets('stash overlap dialog lists files and wires cancel and apply', (
    tester,
  ) async {
    final safety = _StashSafetyFake();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stashSafetyOperationsProvider.overrideWithValue(safety),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ElevatedButton(
                onPressed: () => ref
                    .read(gitActionsControllerProvider)
                    .stashPop(context, repo, 0),
                child: const Text('Pop stash'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pop stash'));
    await tester.pumpAndSettle();
    expect(find.text('same file.txt'), findsOneWidget);
    expect(find.text('other.txt'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(safety.preserveCalls, 0);

    await tester.tap(find.text('Pop stash'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stash my changes and pop'));
    await tester.pumpAndSettle();
    expect(safety.preserveCalls, 1);
    expect(safety.pop, isTrue);
  });
}
