import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/ui/bottom_panel/diff_view.dart';
import '../../_helpers/diff_view_harness.dart';

void main() {
  testWidgets('diff is wrapped in a SelectionArea, with headers excluded',
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

    // The diff content is selectable.
    expect(find.byType(SelectionArea), findsOneWidget);

    // SelectionArea installs an enabled SelectionContainer over everything;
    // chrome must be wrapped in a *disabled* one (registrar == null) so it is
    // skipped by selection/copy. Verify hunk header + file path are disabled,
    // and the code content is not.
    bool hasDisabledAncestor(Finder of) {
      final containers = tester.widgetList<SelectionContainer>(
        find.ancestor(of: of, matching: find.byType(SelectionContainer)),
      );
      return containers.any((c) => c.registrar == null);
    }

    expect(
      hasDisabledAncestor(find.text('@@ -1,1 +1,2 @@')),
      isTrue,
      reason: 'hunk header must be excluded from selection',
    );
    expect(
      hasDisabledAncestor(find.text('lib/a.dart')),
      isTrue,
      reason: 'file path header must be excluded from selection',
    );
    expect(
      hasDisabledAncestor(find.textContaining('const x = 1;')),
      isFalse,
      reason: 'code content must remain selectable',
    );
  });
}
