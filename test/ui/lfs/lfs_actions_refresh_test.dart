import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git_lfs/git_lfs_models.dart';
import 'package:gitopen/application/git_lfs/git_lfs_operations.dart';
import 'package:gitopen/application/git_lfs/git_lfs_service.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/lfs/lfs_actions_controller.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

import '../../_helpers/operations.dart';

const _status = GitLfsStatus(
  isInstalled: true,
  version: '3.6.1',
  isRepoConfigured: true,
  hasAttributes: true,
);

void main() {
  final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');

  testWidgets('a failing LFS reload ends as a refresh failure, not a failed '
      'track', (tester) async {
    var patternLoads = 0;
    final host = await _pumpHost(
      tester,
      overrides: [
        _serviceOverride(_TrackLfs()),
        gitLfsStatusProvider.overrideWith((ref, r) async => _status),
        gitLfsTrackedPatternsProvider.overrideWith((ref, r) {
          patternLoads++;
          return patternLoads == 1
              ? Future.value(const <GitLfsTrackedPattern>[])
              : Future<List<GitLfsTrackedPattern>>.error(
                  StateError('git lfs track --list failed'),
                );
        }),
        gitLfsFilesProvider.overrideWith((ref, r) async => const []),
      ],
      watch: (ref) => ref
        ..watch(gitLfsStatusProvider(repo))
        ..watch(gitLfsTrackedPatternsProvider(repo))
        ..watch(gitLfsFilesProvider(repo)),
    );

    final result = await host.container
        .read(lfsActionsControllerProvider)
        .track(host.context, repo, '*.psd');
    await tester.pump();

    expect(patternLoads, 2, reason: 'the panel was asked to reload');
    expect(
      result.outcome,
      ActionOutcome.success,
      reason: 'git lfs track itself ran',
    );
    final ops = host.container.read(operationsProvider);
    expect(ops.map((o) => o.errorMessage), [refreshFailureMessage]);
    expect(ops.single.onRetry, isNotNull);
  });

  testWidgets('LFS pending holds until the panel reloads', (tester) async {
    final reload = Completer<List<GitLfsTrackedPattern>>();
    var patternLoads = 0;
    final host = await _pumpHost(
      tester,
      overrides: [
        _serviceOverride(_TrackLfs()),
        gitLfsStatusProvider.overrideWith((ref, r) async => _status),
        gitLfsTrackedPatternsProvider.overrideWith((ref, r) {
          patternLoads++;
          return patternLoads == 1
              ? Future.value(const <GitLfsTrackedPattern>[])
              : reload.future;
        }),
        gitLfsFilesProvider.overrideWith((ref, r) async => const []),
      ],
      watch: (ref) => ref
        ..watch(gitLfsStatusProvider(repo))
        ..watch(gitLfsTrackedPatternsProvider(repo))
        ..watch(gitLfsFilesProvider(repo)),
    );

    var done = false;
    unawaited(
      host.container
          .read(lfsActionsControllerProvider)
          .track(host.context, repo, '*.psd')
          .then((_) => done = true),
    );
    await tester.pump();
    await tester.pump();
    expect(patternLoads, 2);
    expect(done, isFalse);
    expect(host.container.read(lfsSyncBusyProvider(repo)), isTrue);

    reload.complete(const []);
    await tester.pump();
    await tester.pump();
    expect(done, isTrue);
    expect(host.container.read(lfsSyncBusyProvider(repo)), isFalse);
  });

  testWidgets('an LFS view nobody has open is not awaited', (tester) async {
    var fileLoads = 0;
    final host = await _pumpHost(
      tester,
      overrides: [
        _serviceOverride(_TrackLfs()),
        gitLfsStatusProvider.overrideWith((ref, r) async => _status),
        gitLfsTrackedPatternsProvider.overrideWith((ref, r) async => const []),
        gitLfsFilesProvider.overrideWith((ref, r) {
          fileLoads++;
          return Completer<List<GitLfsFile>>().future;
        }),
      ],
      // Only the status header is on screen: no files list, no pattern list.
      watch: (ref) => ref.watch(gitLfsStatusProvider(repo)),
    );

    final result = await host.container
        .read(lfsActionsControllerProvider)
        .track(host.context, repo, '*.psd');

    expect(result.outcome, ActionOutcome.success);
    expect(fileLoads, 0, reason: 'a closed list needs no git process');
  });

  testWidgets('a failing reload after an LFS fetch leaves the fetch '
      'successful', (tester) async {
    var fileLoads = 0;
    final host = await _pumpHost(
      tester,
      overrides: [
        _serviceOverride(_FetchLfs()),
        gitLfsStatusProvider.overrideWith((ref, r) async => _status),
        gitLfsTrackedPatternsProvider.overrideWith((ref, r) async => const []),
        gitLfsFilesProvider.overrideWith((ref, r) {
          fileLoads++;
          return fileLoads == 1
              ? Future.value(const <GitLfsFile>[])
              : Future<List<GitLfsFile>>.error(
                  StateError('git lfs ls-files failed'),
                );
        }),
      ],
      watch: (ref) => ref
        ..watch(gitLfsStatusProvider(repo))
        ..watch(gitLfsFilesProvider(repo)),
    );

    final result = (await tester.runAsync(
      () => host.container
          .read(lfsActionsControllerProvider)
          .fetch(host.context, repo),
    ))!;
    await tester.pump();

    expect(result.outcome, ActionOutcome.success);
    final ops = host.container.read(operationsProvider);
    expect(
      ops.where((o) => o.label == 'Git LFS fetch').single.status,
      OperationStatus.success,
      reason: 'the transfer itself did not fail',
    );
    expect(
      ops.where((o) => o.errorMessage == refreshFailureMessage),
      hasLength(1),
    );
  });

  testWidgets('LFS fetch pending holds until the file list reloads', (
    tester,
  ) async {
    late Completer<List<GitLfsFile>> reload;
    var fileLoads = 0;
    final host = await _pumpHost(
      tester,
      overrides: [
        _serviceOverride(_FetchLfs()),
        gitLfsStatusProvider.overrideWith((ref, r) async => _status),
        gitLfsTrackedPatternsProvider.overrideWith((ref, r) async => const []),
        gitLfsFilesProvider.overrideWith((ref, r) {
          fileLoads++;
          return fileLoads == 1
              ? Future.value(const <GitLfsFile>[])
              : reload.future;
        }),
      ],
      watch: (ref) => ref
        ..watch(gitLfsStatusProvider(repo))
        ..watch(gitLfsFilesProvider(repo)),
    );

    // The transfer resumes through a root-zone future, so it runs on the real
    // event loop, and so does the completer it waits on.
    await tester.runAsync(() async {
      reload = Completer<List<GitLfsFile>>();
      var done = false;
      final fetch = host.container
          .read(lfsActionsControllerProvider)
          .fetch(host.context, repo)
          .then((_) => done = true);
      for (var i = 0; i < 100 && fileLoads < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fileLoads, 2);
      expect(done, isFalse);
      expect(host.container.read(lfsSyncBusyProvider(repo)), isTrue);

      reload.complete(const []);
      await fetch;
      expect(host.container.read(lfsSyncBusyProvider(repo)), isFalse);
    });
  });

  testWidgets('an LFS fetch does not await a list nobody has open', (
    tester,
  ) async {
    var fileLoads = 0;
    final host = await _pumpHost(
      tester,
      overrides: [
        _serviceOverride(_FetchLfs()),
        gitLfsStatusProvider.overrideWith((ref, r) async => _status),
        gitLfsTrackedPatternsProvider.overrideWith((ref, r) async => const []),
        gitLfsFilesProvider.overrideWith((ref, r) {
          fileLoads++;
          return Completer<List<GitLfsFile>>().future;
        }),
      ],
      watch: (ref) => ref.watch(gitLfsStatusProvider(repo)),
    );

    final result = (await tester.runAsync(
      () => host.container
          .read(lfsActionsControllerProvider)
          .fetch(host.context, repo),
    ))!;

    expect(result.outcome, ActionOutcome.success);
    expect(fileLoads, 0, reason: 'a closed list needs no git process');
  });
}

Override _serviceOverride(GitLfsOperations lfs) =>
    gitLfsServiceProvider.overrideWithValue(
      GitLfsService(
        lfs: lfs,
        resolveProfile: (_) async => null,
        errorText: (e) => '$e',
      ),
    );

/// Pumps a host that watches the LFS providers the test declares and hands
/// back the context the controller needs plus the container to inspect.
Future<({BuildContext context, ProviderContainer container})> _pumpHost(
  WidgetTester tester, {
  required List<Override> overrides,
  required void Function(WidgetRef ref) watch,
}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        operationsProvider.overrideWith(
          (ref) => OperationsNotifier(InMemoryActivityLog()),
        ),
        ...overrides,
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              captured = context;
              watch(ref);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (
    context: captured,
    container: ProviderScope.containerOf(captured, listen: false),
  );
}

final class _TrackLfs implements GitLfsOperations {
  @override
  Future<GitResult<void>> track(RepoLocation repo, String pattern) async =>
      const GitSuccess(null);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

final class _FetchLfs implements GitLfsOperations {
  @override
  Stream<GitProgress> fetch(RepoLocation repo, {AuthSpec? auth}) =>
      Stream<GitProgress>.fromIterable(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}
