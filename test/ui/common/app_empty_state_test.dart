import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/common/app_empty_state.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData(
    extensions: [
      AppPalette.dark(),
      const AppSpacing.desktop(),
      const AppRadii.desktop(),
      const AppTypography.desktop(),
      const AppMotion.standard(),
    ],
  ),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('renders icon, title, message and optional action', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        AppEmptyState(
          icon: Icons.inbox_outlined,
          title: 'No open pull requests',
          message: 'The repository has no PRs ready for review.',
          actionIcon: Icons.refresh,
          actionLabel: 'Refresh',
          onAction: () => taps++,
        ),
      ),
    );

    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    expect(find.text('No open pull requests'), findsOneWidget);
    expect(
      find.text('The repository has no PRs ready for review.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Refresh'));
    expect(taps, 1);
  });

  testWidgets('message is an optional hint', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppEmptyState(
          icon: Icons.inbox_outlined,
          title: 'No open pull requests',
        ),
      ),
    );

    expect(find.text('No open pull requests'), findsOneWidget);
  });
}
