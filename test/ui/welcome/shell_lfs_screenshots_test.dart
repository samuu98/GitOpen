import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_profile_store.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/application/git_lfs/git_lfs_models.dart';
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
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/dialogs/add_worktree_dialog.dart';
import 'package:gitopen/ui/dialogs/clone_dialog.dart';
import 'package:gitopen/ui/lfs/lfs_actions_controller.dart';
import 'package:gitopen/ui/lfs/lfs_panel.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/status_bar/status_bar.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/welcome/welcome_screen.dart';

import '../../_helpers/screenshot.dart';

final _screenshots = PipelineScreenshotComparator('ux-l7-shell-lfs');
const _repo = RepoLocation(RepoId('repo'), 'C:/work/repo', 'repo');

Widget _frame(AppPalette palette, Key key, Widget child) => RepaintBoundary(
  key: key,
  child: screenshotApp(
    theme: ThemeData(
      fontFamily: 'Roboto',
      brightness: palette.bg0.computeLuminance() < 0.5
          ? Brightness.dark
          : Brightness.light,
      extensions: [
        palette,
        const AppSpacing.desktop(),
        const AppRadii.desktop(),
        const AppTypography.desktop(),
        const AppMotion.standard(),
      ],
    ),
    home: Scaffold(
      backgroundColor: palette.bg0,
      body: ColoredBox(
        color: palette.bg0,
        child: SizedBox(width: 900, height: 520, child: child),
      ),
    ),
  ),
);

Future<void> _capture(String name, Key key) =>
    expectLater(find.byKey(key), matchesGoldenFile('$name.png'));

List<Override> _repositoryOverrides({
  required Future<GraphData> Function() graph,
  OperationsNotifier? operations,
}) => [
  repositoryRegistryProvider.overrideWithValue(_Registry()),
  repositoryValidatorProvider.overrideWithValue(const _Validator()),
  if (operations != null) operationsProvider.overrideWith((ref) => operations),
  repoStatusProvider.overrideWith(
    (ref, repo) async =>
        const RepoStatus(isDetached: false, isBare: false, entries: []),
  ),
  sidebarDataProvider.overrideWith(
    (ref, repo) async => SidebarData([], [], [], [], [], []),
  ),
  commitGraphDataProvider.overrideWith((ref, repo) => graph()),
  branchesProvider.overrideWith((ref, repo) async => []),
  repoStateProvider.overrideWith((ref, repo) async => InProgressOp.none),
  repoActiveProfileProvider.overrideWith((ref, repo) async => null),
];

Widget _lfs({
  required bool pending,
  required bool error,
  required bool refreshed,
}) => ProviderScope(
  overrides: [
    lfsSyncBusyProvider.overrideWith((ref, repo) => pending),
    gitLfsStatusProvider.overrideWith((ref, repo) async {
      if (error) throw StateError('git lfs status failed');
      return const GitLfsStatus(
        isInstalled: true,
        version: '3.6.1',
        isRepoConfigured: true,
        hasAttributes: true,
      );
    }),
    gitLfsTrackedPatternsProvider.overrideWith(
      (ref, repo) async => refreshed
          ? const [
              GitLfsTrackedPattern(
                pattern: '*.psd',
                attributes: 'filter=lfs diff=lfs merge=lfs -text',
                source: '.gitattributes',
              ),
            ]
          : <GitLfsTrackedPattern>[],
    ),
    gitLfsFilesProvider.overrideWith((ref, repo) async => []),
  ],
  child: const LfsPanel(repo: _repo),
);

void main() {
  setUpAll(() async {
    await loadAppFonts();
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root != null) {
      final file = File(
        '$root/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      );
      if (file.existsSync()) {
        final bytes = file.readAsBytesSync();
        await (FontLoader(
          'monospace',
        )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
      }
    }
  });

  for (final (name, palette) in [
    ('dark', AppPalette.dark()),
    ('light', AppPalette.light()),
  ]) {
    testWidgets('$name clone progress and ready render real widgets', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 520));
      final old = goldenFileComparator;
      goldenFileComparator = _screenshots;
      addTearDown(() => goldenFileComparator = old);
      final key = GlobalKey();
      final stream = StreamController<GitProgress>();
      final graph = Completer<GraphData>();
      final write = _Write(stream: stream.stream);
      final ops = OperationsNotifier(_LogStore());
      final container = ProviderContainer(
        overrides: [
          ..._repositoryOverrides(graph: () => graph.future, operations: ops),
          gitWriteOperationsProvider.overrideWithValue(write),
          authProfileStoreProvider.overrideWithValue(_Profiles()),
          gitLfsStatusProvider.overrideWith(
            (ref, repo) async => const GitLfsStatus(
              isInstalled: true,
              version: '3.6.1',
              isRepoConfigured: true,
              hasAttributes: true,
            ),
          ),
          gitLfsTrackedPatternsProvider.overrideWith((ref, repo) async => []),
          gitLfsFilesProvider.overrideWith((ref, repo) async => []),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _frame(
            palette,
            key,
            Consumer(
              builder: (context, ref, child) =>
                  ref.watch(activeWorkspaceIdProvider) == null
                  ? Center(
                      child: TextButton(
                        onPressed: () => CloneDialog.show(context),
                        child: const Text('Open clone'),
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: _lfs(
                            pending: false,
                            error: false,
                            refreshed: true,
                          ),
                        ),
                        const StatusBar(),
                      ],
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
      await tester.enterText(find.byType(TextField).at(1), _repo.path);
      await tester.tap(find.text('Clone'));
      await tester.pump();
      await stream.close();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(CloneDialog), findsOneWidget);
      expect(container.read(activeWorkspaceIdProvider), isNull);
      await _capture('${name}_clone_progress', key);

      graph.complete(GraphData([], {}, 0, hasMore: false));
      await tester.pumpAndSettle();
      expect(find.byType(CloneDialog), findsNothing);
      expect(find.byType(StatusBar), findsOneWidget);
      await _capture('${name}_clone_ready', key);
    });

    testWidgets('$name open recent pending renders WelcomeScreen', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 520));
      final old = goldenFileComparator;
      goldenFileComparator = _screenshots;
      addTearDown(() => goldenFileComparator = old);
      final key = GlobalKey();
      final graph = Completer<GraphData>();
      final ops = OperationsNotifier(_LogStore());
      final container = ProviderContainer(
        overrides: _repositoryOverrides(
          graph: () => graph.future,
          operations: ops,
        ),
      );
      addTearDown(container.dispose);
      await container.read(workspaceManagerProvider.notifier).loadAll();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _frame(palette, key, const WelcomeScreen()),
        ),
      );
      await tester.tap(find.text('repo'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.text('Opening repository…'), findsOneWidget);
      await _capture('${name}_open_recent_progress', key);
    });

    testWidgets('$name add worktree pending renders AddWorktreeDialog', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 520));
      final old = goldenFileComparator;
      goldenFileComparator = _screenshots;
      addTearDown(() => goldenFileComparator = old);
      final key = GlobalKey();
      final write = _Write();
      final reload = Completer<SidebarData>();
      var loads = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gitWriteOperationsProvider.overrideWithValue(write),
            sidebarDataProvider.overrideWith((ref, repo) {
              loads++;
              return loads == 1
                  ? Future.value(SidebarData([], [], [], [], [], []))
                  : reload.future;
            }),
          ],
          child: _frame(
            palette,
            key,
            Consumer(
              builder: (context, ref, child) {
                ref.watch(sidebarDataProvider(_repo));
                return Center(
                  child: TextButton(
                    onPressed: () => AddWorktreeDialog.show(context, _repo),
                    child: const Text('Add'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'C:/work/new-tree');
      await tester.tap(find.text('Create'));
      await tester.pump();
      write.worktreeDone.complete(const GitSuccess(null));
      await tester.pump(const Duration(milliseconds: 350));
      expect(loads, 2);
      expect(find.byType(AddWorktreeDialog), findsOneWidget);
      await _capture('${name}_add_worktree_pending', key);
    });

    testWidgets('$name status hover and focus render StatusBar', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 520));
      final old = goldenFileComparator;
      goldenFileComparator = _screenshots;
      addTearDown(() => goldenFileComparator = old);
      final key = GlobalKey();
      final ops = OperationsNotifier(_LogStore());
      final container = ProviderContainer(
        overrides: _repositoryOverrides(
          graph: () async => GraphData([], {}, 0, hasMore: false),
          operations: ops,
        ),
      );
      addTearDown(container.dispose);
      await container.read(workspaceManagerProvider.notifier).loadAll();
      container.read(activeWorkspaceIdProvider.notifier).state = _repo.id;
      ops.start(OpKind.other, 'Refreshing');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _frame(
            palette,
            key,
            const Align(
              alignment: Alignment.bottomCenter,
              child: StatusBar(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final surfaces = [
        find.widgetWithText(AppInteractiveSurface, _repo.path),
        find.widgetWithText(AppInteractiveSurface, 'no account'),
        find.widgetWithText(AppInteractiveSurface, '1 op'),
      ];
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      for (final surface in surfaces) {
        await mouse.moveTo(tester.getCenter(surface));
        await tester.pumpAndSettle();
        final box = tester.widget<AnimatedContainer>(
          find.descendant(
            of: surface,
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(
          (box.decoration! as BoxDecoration).color,
          palette.interactionHover,
        );
      }
      await _capture('${name}_status_hover', key);
      await mouse.removePointer();
      for (final surface in surfaces) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final box = tester.widget<AnimatedContainer>(
          find.descendant(
            of: surface,
            matching: find.byType(AnimatedContainer),
          ),
        );
        expect(
          (box.decoration! as BoxDecoration).border!.top.color,
          palette.interactionFocusRing,
        );
      }
      await _capture('${name}_status_focus', key);
    });

    testWidgets('$name LFS states render LfsPanel', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 520));
      final old = goldenFileComparator;
      goldenFileComparator = _screenshots;
      addTearDown(() => goldenFileComparator = old);
      Future<void> capture(String label, Widget child) async {
        final key = GlobalKey();
        await tester.pumpWidget(_frame(palette, key, child));
        await tester.pumpAndSettle();
        expect(find.byType(LfsPanel), findsOneWidget);
        await _capture('${name}_$label', key);
      }

      await capture(
        'lfs_track_pending',
        _lfs(pending: true, error: false, refreshed: false),
      );
      await capture(
        'lfs_refreshed',
        _lfs(pending: false, error: false, refreshed: true),
      );
      await capture(
        'lfs_error',
        _lfs(pending: false, error: true, refreshed: false),
      );
    });
  }
}

final class _Registry implements RepositoryRegistry {
  @override
  Future<List<RepoLocation>> list() async => [_repo];

  @override
  Future<RepoLocation> add(String path) async => _repo;

  @override
  Future<void> touchLastOpened(RepoId id) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

final class _Validator implements RepositoryValidator {
  const _Validator();

  @override
  Future<String> validate(String path) async => path;
}

final class _Write implements GitWriteOperations {
  _Write({this.stream});
  final Stream<GitProgress>? stream;
  final worktreeDone = Completer<GitResult<void>>();

  @override
  Stream<GitProgress> clone(String url, String destination, {AuthSpec? auth}) =>
      stream!;

  @override
  Future<GitResult<void>> addWorktree(
    RepoLocation repo,
    String path, {
    String? newBranch,
    String? ref,
  }) => worktreeDone.future;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
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
      throw UnimplementedError(invocation.memberName.toString());
}

final class _LogStore implements ActivityLogStore {
  @override
  Future<void> upsert(RunningOperation operation) async {}

  @override
  Future<List<RunningOperation>> recent({int limit = 50}) async => [];

  @override
  Future<void> clearCompleted() async {}
}
