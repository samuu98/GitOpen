import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_profile_store.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
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
import 'package:gitopen/ui/dialogs/clone_dialog.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  testWidgets('clone waits for initial views and retries a graph load error', (
    tester,
  ) async {
    final stream = StreamController<GitProgress>();
    final graph = Completer<GraphData>();
    final retryGraph = Completer<GraphData>();
    var graphLoads = 0;
    final container = ProviderContainer(
      overrides: [
        gitWriteOperationsProvider.overrideWithValue(
          _CloneWrite(stream.stream),
        ),
        authProfileStoreProvider.overrideWithValue(_Profiles()),
        operationsProvider.overrideWith(
          (ref) => OperationsNotifier(_ActivityStore()),
        ),
        repositoryRegistryProvider.overrideWithValue(_Registry()),
        repositoryValidatorProvider.overrideWithValue(const _Validator()),
        repoStatusProvider.overrideWith(
          (ref, repo) async =>
              const RepoStatus(isDetached: false, isBare: false, entries: []),
        ),
        sidebarDataProvider.overrideWith(
          (ref, repo) async => SidebarData([], [], [], [], [], []),
        ),
        commitGraphDataProvider.overrideWith((ref, repo) {
          graphLoads++;
          return graphLoads == 1 ? graph.future : retryGraph.future;
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => CloneDialog.show(context),
                child: const Text('Open clone'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open clone'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(0),
      'https://github.com/u/r.git',
    );
    await tester.enterText(find.byType(TextField).at(1), 'C:/repo');
    await tester.tap(find.text('Clone'));
    await tester.pump();
    await stream.close();
    await tester.pump();
    expect(find.text('Clone repository'), findsOneWidget);
    expect(container.read(activeWorkspaceIdProvider), isNull);
    graph.completeError(StateError('git log failed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Could not load repository'), findsOneWidget);
    await tester.tap(find.text('Retry').first);
    await tester.pump();
    expect(container.read(activeWorkspaceIdProvider), isNull);
    retryGraph.complete(GraphData([], {}, 0, hasMore: false));
    await tester.pumpAndSettle();
    expect(container.read(activeWorkspaceIdProvider), const RepoId('repo'));
    expect(find.text('Clone repository'), findsNothing);
  });

  testWidgets('busy clone ignores barrier and Escape; Cancel stops git', (
    tester,
  ) async {
    final stream = StreamController<GitProgress>();
    var stopped = false;
    stream.onCancel = () => stopped = true;
    final write = _CloneWrite(stream.stream);
    final ops = OperationsNotifier(_ActivityStore());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitWriteOperationsProvider.overrideWithValue(write),
          authProfileStoreProvider.overrideWithValue(_Profiles()),
          operationsProvider.overrideWith((ref) => ops),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => CloneDialog.show(context),
                child: const Text('Open clone'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open clone'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(0),
      'https://github.com/u/r.git',
    );
    await tester.enterText(find.byType(TextField).at(1), 'C:/repo');
    await tester.tap(find.text('Clone'));
    await tester.pump();
    expect(write.calls, 1);
    expect(write.auth, const AuthHttpsPat(username: 'u', token: 'secret'));
    await tester.tapAt(const Offset(2, 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Clone repository'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(stopped, isTrue);
    expect(ops.state.single.status, OperationStatus.cancelled);
    expect(find.text('Clone repository'), findsNothing);
  });
}

final class _Registry implements RepositoryRegistry {
  @override
  Future<RepoLocation> add(String path) async =>
      const RepoLocation(RepoId('repo'), 'C:/repo', 'repo');
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

final class _CloneWrite implements GitWriteOperations {
  _CloneWrite(this.stream);
  final Stream<GitProgress> stream;
  int calls = 0;
  AuthSpec? auth;

  @override
  Stream<GitProgress> clone(String url, String destination, {AuthSpec? auth}) {
    calls++;
    this.auth = auth;
    return stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

final class _Profiles implements AuthProfileStore {
  @override
  Future<List<AuthProfile>> forHost(String host) async => [
    const AuthProfile(
      id: 'profile',
      host: 'github.com',
      username: 'u',
      spec: AuthHttpsPat(username: 'u', token: 'secret'),
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

final class _ActivityStore implements ActivityLogStore {
  @override
  Future<void> upsert(RunningOperation operation) async {}

  @override
  Future<List<RunningOperation>> recent({int limit = 50}) async => [];

  @override
  Future<void> clearCompleted() async {}
}
