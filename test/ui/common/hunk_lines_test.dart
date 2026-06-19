import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/ui/common/diff_line_row.dart';
import 'package:gitopen/ui/common/diff_prefs.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

Widget _host(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 300, height: 200, child: child),
          ),
        ),
      ),
    );

void main() {
  testWidgets('long unified line is horizontally scrollable', (tester) async {
    final lines = [
      DiffLine(kind: DiffLineKind.addition, content: 'x' * 400, newLine: 1),
    ];

    await tester.pumpWidget(_host(HunkLines(lines: lines)));

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.axis, Axis.horizontal);
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('long side-by-side line is horizontally scrollable', (
    tester,
  ) async {
    final lines = [
      DiffLine(kind: DiffLineKind.deletion, content: 'z' * 400, oldLine: 1),
      DiffLine(kind: DiffLineKind.addition, content: 'w' * 400, newLine: 1),
    ];

    await tester.pumpWidget(
      _host(
        HunkLines(lines: lines),
        overrides: [
          diffViewModeProvider.overrideWith((ref) => DiffViewMode.sideBySide),
        ],
      ),
    );

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
  });
}
