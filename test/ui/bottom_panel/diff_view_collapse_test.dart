import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/ui/bottom_panel/diff_view.dart';
import '../../_helpers/diff_view_harness.dart';

void main() {
  testWidgets('tapping a file header collapses and re-expands its diff',
      (tester) async {
    final diff = diffOf([fileDiffFixture('lib/a.dart')]);
    final repo = testRepo();
    await tester.pumpWidget(
      wrapWithApp(
        DiffView(repo: repo, sha: CommitSha('a' * 40)),
        overrides: [
          gitReadOperationsProvider.overrideWithValue(FakeDiffReadOps(diff)),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Expanded by default: the code line shows.
    expect(find.textContaining('const x = 1;'), findsOneWidget);
    expect(find.text('lib/a.dart'), findsOneWidget);

    // Collapse: tap the file header toggle.
    await tester.tap(find.byKey(const Key('collapse-lib/a.dart')));
    await tester.pumpAndSettle();

    // Diff hidden, header still present.
    expect(find.textContaining('const x = 1;'), findsNothing);
    expect(find.text('lib/a.dart'), findsOneWidget);

    // Re-expand.
    await tester.tap(find.byKey(const Key('collapse-lib/a.dart')));
    await tester.pumpAndSettle();
    expect(find.textContaining('const x = 1;'), findsOneWidget);
  });
}
