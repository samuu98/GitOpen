import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/common/skeleton.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(extensions: [AppPalette.dark()]),
      home: Scaffold(
        body: SizedBox(width: 240, height: 320, child: child),
      ),
    );

void main() {
  testWidgets('SkeletonList renders pulsing placeholder bars', (tester) async {
    await tester.pumpWidget(
      _host(const SkeletonList(rows: 6, rowHeight: 11, gap: 15)),
    );
    await tester.pump();
    expect(find.byType(FractionallySizedBox), findsWidgets);
    // The pulse animation advances without throwing.
    await tester.pump(const Duration(milliseconds: 500));
    // Unmount cleanly — the repeating ticker is cancelled on dispose.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('SkeletonList caps the bar count to the available height',
      (tester) async {
    // 320px tall at ~26px per row → far fewer than the 100 requested.
    await tester.pumpWidget(
      _host(const SkeletonList(rows: 100, rowHeight: 11, gap: 15)),
    );
    await tester.pump();
    final bars = tester.widgetList(find.byType(FractionallySizedBox)).length;
    expect(bars, greaterThan(0));
    expect(bars, lessThan(100));
    await tester.pumpWidget(const SizedBox());
  });
}
