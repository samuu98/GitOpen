import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/common/divergence_badge.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

Future<void> _pump(WidgetTester t, int ahead, int behind) => t.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Scaffold(body: DivergenceBadge(ahead: ahead, behind: behind)),
      ),
    );

void main() {
  testWidgets('shows both arrows', (t) async {
    await _pump(t, 2, 3);
    expect(find.text('↑2 ↓3'), findsOneWidget);
  });
  testWidgets('omits the zero side', (t) async {
    await _pump(t, 2, 0);
    expect(find.text('↑2'), findsOneWidget);
    expect(find.textContaining('↓'), findsNothing);
  });
  testWidgets('renders nothing when in sync', (t) async {
    await _pump(t, 0, 0);
    expect(find.textContaining('↑'), findsNothing);
    expect(find.textContaining('↓'), findsNothing);
  });
}
