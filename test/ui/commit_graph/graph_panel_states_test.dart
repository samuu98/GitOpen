import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/repo_state_provider.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_panel.dart';
import 'package:gitopen/ui/commit_graph/commit_graph_providers.dart';
import 'package:gitopen/ui/common/app_empty_state.dart';
import 'package:gitopen/ui/common/app_panel_state.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  testWidgets(
    'graph loading, error retry, and empty repository use panel states',
    (tester) async {
      final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
      var calls = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            commitGraphDataProvider(repo).overrideWith((ref) async {
              calls++;
              if (calls == 1) throw StateError('graph unavailable');
              return GraphData([], {}, 0, hasMore: false);
            }),
            bisectStateProvider(repo).overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: ThemeData(extensions: [AppPalette.dark()]),
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 500,
                child: CommitGraphPanel(repo: repo),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(AppLoadingState), findsOneWidget);
      await tester.pump();
      await tester.pump();
      expect(find.byType(AppErrorState), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(calls, 2);
      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.text('No commits in this repository'), findsOneWidget);
    },
  );
}
