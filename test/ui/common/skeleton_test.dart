import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/common/skeleton.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(extensions: [AppPalette.dark()]),
      home: Scaffold(body: child),
    );

void main() {
  group('SkeletonList', () {
    testWidgets('does not overflow in a panel shorter than its rows',
        (tester) async {
      // 18 rows × 11px + 17 gaps × 15px + 16px padding top/bottom = 485px.
      // Give it only 324px — the height the commit graph panel had when the
      // app logged "RenderFlex overflowed by 161 pixels".
      await tester.pumpWidget(_wrap(
        const SizedBox(
          height: 324,
          width: 400,
          child: SkeletonList(rows: 18, rowHeight: 11, gap: 15),
        ),
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders all requested rows when there is room',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const SizedBox(
          height: 1000,
          width: 400,
          child: SkeletonList(rows: 6, rowHeight: 11, gap: 15),
        ),
      ));
      expect(tester.takeException(), isNull);
      // 6 bars (FractionallySizedBox wraps each one).
      expect(find.byType(FractionallySizedBox), findsNWidgets(6));
    });
  });
}
