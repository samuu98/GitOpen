import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/hunk_row.dart';

void main() {
  testWidgets('long working-copy line is horizontally scrollable', (
    tester,
  ) async {
    final hunk = DiffHunk(
      oldStart: 1,
      oldCount: 1,
      newStart: 1,
      newCount: 1,
      header: '@@ -1 +1 @@',
      lines: [
        DiffLine(kind: DiffLineKind.addition, content: 'y' * 400, newLine: 1),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              height: 200,
              child: HunkRow(
                hunk: hunk,
                index: 0,
                staged: false,
                isChecked: false,
                onToggle: () {},
                selectedLines: const <int>{},
                onToggleLine: (_) {},
                onAction: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.axis, Axis.horizontal);
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
  });
}
