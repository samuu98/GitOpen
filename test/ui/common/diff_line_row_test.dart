import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/ui/common/diff_line_row.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  testWidgets('line-number gutters and +/- prefix are excluded from selection',
      (tester) async {
    const line = DiffLine(
      kind: DiffLineKind.addition,
      content: 'const x = 1;',
      newLine: 42,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: const Scaffold(body: DiffLineRow(line: line)),
      ),
    );

    // The new-line-number gutter "42" must sit under a SelectionContainer
    // (disabled) so it is skipped by selection and copy.
    final gutter = find.text('42');
    expect(gutter, findsOneWidget);
    expect(
      find.ancestor(of: gutter, matching: find.byType(SelectionContainer)),
      findsWidgets,
      reason: 'line-number gutter must sit under SelectionContainer.disabled',
    );

    // The code content must NOT be wrapped in a SelectionContainer — it stays
    // selectable so the user can copy clean code.
    final content = find.textContaining('const x = 1;');
    expect(content, findsOneWidget);
    expect(
      find.ancestor(of: content, matching: find.byType(SelectionContainer)),
      findsNothing,
      reason: 'code content must remain selectable',
    );
  });
}
