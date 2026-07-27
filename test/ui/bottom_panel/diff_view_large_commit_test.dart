import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/domain/diff/file_diff.dart';
import 'package:gitopen/ui/bottom_panel/diff_view.dart';
import 'package:gitopen/ui/common/diff_line_row.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

import '../../_helpers/diff_view_harness.dart';

/// A commit touching a lot of files used to build EVERY file's every diff line
/// in one frame — the whole list lives in a `SingleChildScrollView`, so nothing
/// is lazy — which froze the app for seconds on a big commit. Files past a
/// render budget now start collapsed (header only) and expand on demand.
FileDiff _file(String path, int lines) => fileDiffFixture(
      path,
      linesAdded: lines,
      lines: [
        for (var i = 0; i < lines; i++)
          DiffLine(
            kind: DiffLineKind.addition,
            content: 'line $i of $path',
            newLine: i + 1,
          ),
      ],
    );

void main() {
  testWidgets('a many-file commit does not build every diff line upfront',
      (tester) async {
    const fileCount = 120;
    const linesPerFile = 100; // 12 000 lines in total
    final diff = diffOf([
      for (var i = 0; i < fileCount; i++) _file('lib/file_$i.dart', linesPerFile),
    ]);

    await tester.pumpWidget(
      wrapWithApp(
        DiffView(repo: testRepo(), sha: CommitSha('a' * 40)),
        overrides: [
          gitReadOperationsProvider.overrideWithValue(FakeDiffReadOps(diff)),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Every file still gets a header, so the user sees the full file list and
    // "reveal this file" keeps working.
    expect(find.byKey(const Key('collapse-lib/file_0.dart')), findsOneWidget);
    expect(find.byKey(const Key('collapse-lib/file_119.dart')), findsOneWidget);

    // But the number of rendered diff lines is bounded, not fileCount *
    // linesPerFile.
    final rendered = tester.widgetList<DiffLineRow>(find.byType(DiffLineRow));
    expect(
      rendered.length,
      lessThanOrEqualTo(2500),
      reason: 'diff lines must be bounded by the render budget, not by the '
          'size of the commit',
    );
    expect(rendered, isNotEmpty, reason: 'the first files still render');
  });

  testWidgets('a collapsed file expands on demand', (tester) async {
    final diff = diffOf([
      for (var i = 0; i < 60; i++) _file('lib/file_$i.dart', 200),
    ]);

    await tester.pumpWidget(
      wrapWithApp(
        DiffView(repo: testRepo(), sha: CommitSha('a' * 40)),
        overrides: [
          gitReadOperationsProvider.overrideWithValue(FakeDiffReadOps(diff)),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // The last file is past the budget, so it starts collapsed.
    expect(find.textContaining('line 0 of lib/file_59.dart'), findsNothing);

    // The block is built but far below the fold (the list is not lazy), so
    // scroll it into the viewport before tapping its header.
    final header = find.byKey(const Key('collapse-lib/file_59.dart'));
    await tester.ensureVisible(header);
    await tester.pumpAndSettle();
    await tester.tap(header);
    await tester.pumpAndSettle();

    expect(find.textContaining('line 0 of lib/file_59.dart'), findsOneWidget);
  });

  testWidgets('revealing a file past the budget expands it', (tester) async {
    // Clicking a file in the Commit tab's changed-files list asks the Changes
    // view to reveal it. That target is now very likely to be one of the
    // collapsed ones, so reveal has to expand it, not just scroll to a header.
    final diff = diffOf([
      for (var i = 0; i < 60; i++) _file('lib/file_$i.dart', 200),
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
              width: 900,
              height: 600,
              child: DiffView(repo: testRepo(), sha: CommitSha('a' * 40)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('line 0 of lib/file_50.dart'), findsNothing);

    container.read(revealFilePathProvider.notifier).state = 'lib/file_50.dart';
    await tester.pumpAndSettle();

    expect(container.read(revealFilePathProvider), isNull);
    expect(find.textContaining('line 0 of lib/file_50.dart'), findsOneWidget);
  });

  testWidgets('a small commit is fully expanded, as before', (tester) async {
    final diff = diffOf([_file('lib/a.dart', 5), _file('lib/b.dart', 5)]);

    await tester.pumpWidget(
      wrapWithApp(
        DiffView(repo: testRepo(), sha: CommitSha('a' * 40)),
        overrides: [
          gitReadOperationsProvider.overrideWithValue(FakeDiffReadOps(diff)),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('line 0 of lib/a.dart'), findsOneWidget);
    expect(find.textContaining('line 0 of lib/b.dart'), findsOneWidget);
  });
}
