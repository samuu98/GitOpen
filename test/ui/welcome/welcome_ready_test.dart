import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/operations/activity_log_store.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/workspaces/repository_registry.dart';
import 'package:gitopen/application/workspaces/repository_validator.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_providers.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/welcome/welcome_screen.dart';

void main() {
  testWidgets('recent open remains pending until graph loads and can retry', (
    tester,
  ) async {
    final graph = Completer<GraphData>();
    final retryGraph = Completer<GraphData>();
    var loads = 0;
    final container = ProviderContainer(
      overrides: [
        repositoryRegistryProvider.overrideWithValue(_Registry()),
        repositoryValidatorProvider.overrideWithValue(const _Validator()),
        operationsProvider.overrideWith(
          (ref) => OperationsNotifier(_LogStore()),
        ),
        repoStatusProvider.overrideWith(
          (ref, repo) async =>
              const RepoStatus(isDetached: false, isBare: false, entries: []),
        ),
        sidebarDataProvider.overrideWith(
          (ref, repo) async => SidebarData([], [], [], [], [], []),
        ),
        commitGraphDataProvider.overrideWith((ref, repo) {
          loads++;
          return loads == 1 ? graph.future : retryGraph.future;
        }),
      ],
    );
    addTearDown(container.dispose);
    await container.read(workspaceManagerProvider.notifier).loadAll();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: const Scaffold(body: WelcomeScreen()),
        ),
      ),
    );
    await tester.tap(find.text('repo'));
    await tester.pump();
    expect(find.text('Opening repository…'), findsOneWidget);
    expect(container.read(activeWorkspaceIdProvider), isNull);
    graph.completeError(StateError('git log failed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Could not load repository'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(container.read(activeWorkspaceIdProvider), isNull);
    retryGraph.complete(GraphData([], {}, 0, hasMore: false));
    await tester.pumpAndSettle();
    expect(container.read(activeWorkspaceIdProvider), const RepoId('repo'));
  });

  testWidgets('recent open finishes its operation after welcome unmounts', (
    tester,
  ) async {
    final graph = Completer<GraphData>();
    final ops = OperationsNotifier(_LogStore());
    final container = ProviderContainer(
      overrides: [
        repositoryRegistryProvider.overrideWithValue(_Registry()),
        repositoryValidatorProvider.overrideWithValue(const _Validator()),
        operationsProvider.overrideWith((ref) => ops),
        repoStatusProvider.overrideWith(
          (ref, repo) async =>
              const RepoStatus(isDetached: false, isBare: false, entries: []),
        ),
        sidebarDataProvider.overrideWith(
          (ref, repo) async => SidebarData([], [], [], [], [], []),
        ),
        commitGraphDataProvider.overrideWith((ref, repo) => graph.future),
      ],
    );
    addTearDown(container.dispose);
    await container.read(workspaceManagerProvider.notifier).loadAll();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: const Scaffold(body: WelcomeScreen()),
        ),
      ),
    );
    await tester.tap(find.text('repo'));
    await tester.pump();
    expect(ops.state.single.status, OperationStatus.running);
    await tester.pumpWidget(const SizedBox.shrink());
    graph.complete(GraphData([], {}, 0, hasMore: false));
    await tester.pump();
    expect(ops.state.single.status, OperationStatus.success);
    expect(container.read(activeWorkspaceIdProvider), const RepoId('repo'));
  });
}

final class _Registry implements RepositoryRegistry {
  static const location = RepoLocation(RepoId('repo'), 'C:/repo', 'repo');
  @override
  Future<List<RepoLocation>> list() async => [location];
  @override
  Future<RepoLocation> add(String path) async => location;
  @override
  Future<void> touchLastOpened(RepoId id) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

final class _Validator implements RepositoryValidator {
  const _Validator();
  @override
  Future<String> validate(String path) async => path;
}

final class _LogStore implements ActivityLogStore {
  @override
  Future<void> upsert(RunningOperation operation) async {}
  @override
  Future<List<RunningOperation>> recent({int limit = 50}) async => [];
  @override
  Future<void> clearCompleted() async {}
}
