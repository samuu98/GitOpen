import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/github/github_models.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/github/pull_request_forms.dart';
import 'package:gitopen/ui/github/pull_request_review_drawer.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  testWidgets('PR forms open in AppDialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () => showCreatePullRequestDialog(context),
                  child: const Text('Create PR'),
                ),
                TextButton(
                  onPressed: () => showEditPullRequestDialog(context, _detail),
                  child: const Text('Edit PR'),
                ),
                TextButton(
                  onPressed: () => showMergePullRequestDialog(context),
                  child: const Text('Merge PR'),
                ),
                TextButton(
                  onPressed: () => showLineCommentDialog(
                    context,
                    path: 'lib/main.dart',
                    line: 5,
                    side: 'RIGHT',
                  ),
                  child: const Text('Comment'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    for (final label in ['Create PR', 'Edit PR', 'Merge PR']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(AppDialog))).pop();
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Comment'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('Comment on line 5'), findsOneWidget);
  });
}

final _detail = PullRequestDetail(
  number: 1,
  nodeId: 'node',
  title: 'Title',
  body: 'Body',
  author: 'author',
  state: 'open',
  isDraft: false,
  mergeable: true,
  mergeStateStatus: 'clean',
  baseRef: 'main',
  headRef: 'feature',
  headSha: 'sha',
  htmlUrl: 'https://example.test/pr/1',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);
