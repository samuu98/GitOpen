import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/common/diff_horizontal_scroll.dart';

Widget _host(Widget child, {double width = 300}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, height: 200, child: child),
    ),
  ),
);

void main() {
  testWidgets('scrolls horizontally when content exceeds the viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const DiffHorizontalScroll(child: SizedBox(width: 1000, height: 20)),
      ),
    );

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.axis, Axis.horizontal);
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('content narrower than the viewport does not scroll', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const DiffHorizontalScroll(child: SizedBox(width: 50, height: 20))),
    );

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, 0);
  });
}
