import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/ui/bottom_panel/diff_view.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import '../../_helpers/diff_view_harness.dart';

void main() {
  testWidgets('a reveal request scrolls to the file and is consumed',
      (tester) async {
    final diff = diffOf([
      fileDiffFixture('lib/a.dart'),
      fileDiffFixture('lib/b.dart'),
    ]);
    final container = ProviderContainer(
      overrides: [
        gitReadOperationsProvider.overrideWithValue(FakeDiffReadOps(diff)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: DiffView(repo: testRepo(), sha: CommitSha('a' * 40)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Request reveal of the second file.
    container.read(revealFilePathProvider.notifier).state = 'lib/b.dart';
    await tester.pumpAndSettle();

    // The request is consumed (reset to null) and the target is present.
    expect(container.read(revealFilePathProvider), isNull);
    expect(find.text('lib/b.dart'), findsOneWidget);
  });
}
