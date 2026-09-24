import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/commit_graph/commit_node.dart';
import 'package:gitopen/application/git/bisect_state.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/commits/commit_signature.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_panel.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_providers.dart';
import 'package:gitopen/ui/commit_graph/commit_row.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  testWidgets('graph marks bisect bounds, result, and clears on reset', (
    tester,
  ) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'test');
    final shas = List.generate(4, (i) => CommitSha('${i + 1}' * 40));
    final author = CommitSignature(
      'Ada',
      'ada@example.com',
      DateTime.utc(2026, 9, 24),
    );
    final nodes = [
      for (var i = 0; i < shas.length; i++)
        CommitNode(
          commit: CommitInfo(
            sha: shas[i],
            parentShas: const [],
            author: author,
            committer: author,
            summary: 'Commit $i',
            message: 'Commit $i',
          ),
          lane: 0,
          color: 0,
          topSegments: const [],
          bottomSegments: const [],
        ),
    ];
    BisectState? state = BisectState(
      candidate: shas[0],
      subject: 'Commit 0',
      good: [shas[1]],
      bad: shas[2],
      stepsLeft: 1,
    );
    final boundary = GlobalKey();
    final write = _BisectWrite();
    final container = ProviderContainer(
      overrides: [
        gitActionsServiceProvider.overrideWithValue(
          GitActionsService(
            write: write,
            resolveProfile: (_) async => null,
            errorText: (error) => error.toString(),
          ),
        ),
        commitGraphDataProvider(repo).overrideWith(
          (ref) async => GraphData(nodes, {}, 0, hasMore: false),
        ),
        bisectStateProvider(repo).overrideWith((ref) async => state),
      ],
    );
    addTearDown(container.dispose);
    final font = FontLoader('Roboto')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              r'C:\Users\g.chirico\flutter\bin\cache\artifacts\material_fonts\roboto-regular.ttf',
            ).readAsBytesSync(),
          ),
        ),
      );
    await font.load();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
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
            body: RepaintBoundary(
              key: boundary,
              child: CommitGraphPanel(repo: repo),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Finder marker(String label) => find.descendant(
      of: find.byType(CommitRow),
      matching: find.text(label),
    );
    expect(marker('Candidate'), findsOneWidget);
    expect(marker('Good'), findsOneWidget);
    expect(marker('Bad'), findsOneWidget);

    await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final screenshot = File('build/pipeline/known-limits/bisect-markers.png');
      screenshot.parent.createSync(recursive: true);
      screenshot.writeAsBytesSync(bytes!.buffer.asUint8List());
    });

    state = BisectState(
      candidate: shas[0],
      subject: 'Commit 0',
      good: [shas[1]],
      bad: shas[2],
      firstBad: shas[3],
      stepsLeft: 0,
    );
    container.invalidate(bisectStateProvider(repo));
    await tester.pumpAndSettle();
    expect(marker('First bad'), findsOneWidget);

    state = null;
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(write.resetCalls, 1);
    expect(marker('First bad'), findsNothing);
    expect(marker('Candidate'), findsNothing);
    expect(marker('Good'), findsNothing);
    expect(marker('Bad'), findsNothing);
  });
}

class _BisectWrite implements GitWriteOperations {
  int resetCalls = 0;

  @override
  Future<GitResult<void>> bisectReset(RepoLocation repo) async {
    resetCalls++;
    return const GitSuccess(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}
