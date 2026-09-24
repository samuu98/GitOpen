import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/commit_request.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings_notifier.dart';
import 'package:gitopen/application/settings/settings_store.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/infrastructure/git/git_cli_commit_template_reader.dart';
import 'package:gitopen/infrastructure/git/git_identity_service.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_providers.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/commit_compose.dart';
import 'package:gitopen/ui/working_copy/discard_changes.dart';

import '../../_helpers/operations.dart';
import '../../_helpers/screenshot.dart';
import 'working_copy_screenshot_fonts.dart';

final _screenshots = PipelineScreenshotComparator('ux-l6-working-copy');

class _Settings implements SettingsStore {
  @override
  Future<Map<String, dynamic>> readAll() async => {};
  @override
  Future<void> put(String key, dynamic value) async {}
}

class _ConfigRunner extends GitProcessRunner {
  @override
  Future<String> run(
    String workingDir,
    List<String> args, {
    Duration? timeout,
  }) async => '';
}

class _TemplateReader extends GitCliCommitTemplateReader {
  @override
  Future<String?> read(RepoLocation repo) async => null;
}

class _Write implements GitWriteOperations {
  _Write({this.failCommit = false});
  final bool failCommit;
  int commits = 0;
  int discards = 0;
  @override
  Future<GitResult<CommitSha>> commit(RepoLocation r, CommitRequest req) async {
    commits++;
    if (failCommit) {
      return const GitFailure(GitErrorKind.other, 'commit rejected');
    }
    return GitSuccess(CommitSha('abcdef1'));
  }

  @override
  Future<GitResult<void>> discardChanges(
    RepoLocation r,
    List<String> paths,
  ) async {
    discards++;
    return const GitSuccess(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

const _entry = WorkingFileEntry(
  path: 'a.txt',
  indexState: WorkingFileState.modified,
  workingTreeState: WorkingFileState.modified,
);
const _status = RepoStatus(
  isDetached: false,
  isBare: false,
  entries: [_entry],
);

void main() {
  setUpAll(loadWorkingCopyFonts);
  for (final (themeName, palette) in [
    ('dark', AppPalette.dark()),
    ('light', AppPalette.light()),
  ]) {
    for (final failGraph in [false, true]) {
      testWidgets(
        failGraph
            ? '$themeName commit reports refresh failure and clears busy'
            : '$themeName commit stays busy until graph and status refresh',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(850, 380));
          final previousComparator = goldenFileComparator;
          goldenFileComparator = _screenshots;
          addTearDown(() => goldenFileComparator = previousComparator);
          final key = GlobalKey();
          final repo = RepoLocation(RepoId.newId(), 'unused', 'test');
          final write = _Write();
          final statusGate = Completer<RepoStatus>();
          final graphGate = Completer<GraphData>();
          var statusLoads = 0;
          var graphLoads = 0;
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                operationsProvider.overrideWith(
                  (ref) => OperationsNotifier(InMemoryActivityLog()),
                ),
                appSettingsProvider.overrideWith(
                  (ref) => AppSettingsNotifier(_Settings()),
                ),
                gitCommitTemplateReaderProvider.overrideWithValue(
                  _TemplateReader(),
                ),
                gitWriteOperationsProvider.overrideWithValue(write),
                gitIdentityServiceProvider.overrideWithValue(
                  GitIdentityService(runner: _ConfigRunner()),
                ),
                repoStatusProvider(repo).overrideWith((ref) {
                  statusLoads++;
                  return statusLoads == 1
                      ? Future.value(_status)
                      : statusGate.future;
                }),
                commitGraphDataProvider(repo).overrideWith((ref) {
                  graphLoads++;
                  return graphLoads == 1
                      ? Future.value(
                          GraphData(const [], const {}, 0, hasMore: false),
                        )
                      : graphGate.future;
                }),
              ],
              child: MaterialApp(
                theme: ThemeData(
                  fontFamily: 'Roboto',
                  extensions: [
                    palette,
                    const AppSpacing.desktop(),
                    const AppRadii.desktop(),
                    const AppTypography.desktop(),
                    const AppMotion.standard(),
                  ],
                ),
                home: Scaffold(
                  body: RepaintBoundary(
                    key: key,
                    child: ColoredBox(
                      color: palette.bg0,
                      child: Consumer(
                        builder: (context, ref, _) {
                          ref
                            ..watch(repoStatusProvider(repo))
                            ..watch(commitGraphDataProvider(repo));
                          return CommitCompose(repo: repo, hasStaged: true);
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.enterText(find.byType(TextField), 'Subject');
          await tester.pump();
          await tester.tap(find.text('Commit'));
          await tester.pump();
          expect(write.commits, 1);
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          if (!failGraph) {
            await expectLater(
              find.byKey(key),
              matchesGoldenFile('compose_committing_$themeName.png'),
            );
          }
          statusGate.complete(_status);
          await tester.pump();
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          if (failGraph) {
            graphGate.completeError(StateError('git log failed'));
          } else {
            graphGate.complete(
              GraphData(const [], const {}, 0, hasMore: false),
            );
          }
          await tester.pump();
          expect(find.byType(CircularProgressIndicator), findsNothing);
          if (failGraph) {
            expect(
              find.text('Commit created, but the view could not refresh.'),
              findsOneWidget,
            );
          } else {
            expect(
              tester.widget<TextField>(find.byType(TextField)).controller!.text,
              isEmpty,
            );
            await expectLater(
              find.byKey(key),
              matchesGoldenFile('compose_after_$themeName.png'),
            );
          }
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('discard waits for status refresh', (tester) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'test');
    final write = _Write();
    final statusGate = Completer<RepoStatus>();
    var loads = 0;
    var finished = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitWriteOperationsProvider.overrideWithValue(write),
          repoStatusProvider(repo).overrideWith((ref) {
            loads++;
            return loads == 1 ? Future.value(_status) : statusGate.future;
          }),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                ref.watch(repoStatusProvider(repo));
                return TextButton(
                  onPressed: () async {
                    await discardEntries(context, ref, repo, const [_entry]);
                    finished = true;
                  },
                  child: const Text('Discard'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Discard'));
    await tester.pump();
    expect(write.discards, 1);
    expect(finished, isFalse);
    statusGate.complete(_status);
    await tester.pump();
    expect(finished, isTrue);
  });

  testWidgets('git failure keeps the commit message', (tester) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'test');
    final write = _Write(failCommit: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          operationsProvider.overrideWith(
            (ref) => OperationsNotifier(InMemoryActivityLog()),
          ),
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsNotifier(_Settings()),
          ),
          gitCommitTemplateReaderProvider.overrideWithValue(_TemplateReader()),
          gitWriteOperationsProvider.overrideWithValue(write),
          gitIdentityServiceProvider.overrideWithValue(
            GitIdentityService(runner: _ConfigRunner()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(body: CommitCompose(repo: repo, hasStaged: true)),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Keep this subject');
    await tester.pump();
    await tester.tap(find.text('Commit'));
    await tester.pump();
    expect(write.commits, 1);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Keep this subject',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CommitCompose)),
    );
    expect(
      container.read(operationsProvider).last.errorMessage,
      'commit rejected',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
