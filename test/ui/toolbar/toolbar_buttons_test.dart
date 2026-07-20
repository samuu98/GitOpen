import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/toolbar/toolbar_buttons.dart';

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData(
    extensions: [
      AppPalette.dark(),
      const AppSpacing.desktop(),
      const AppRadii.desktop(),
      const AppTypography.desktop(),
    ],
  ),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('compact toolbar action keeps its tooltip and hides its label', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        ToolbarButton(
          icon: Icons.cloud_download_outlined,
          label: 'Fetch',
          tooltip: 'Fetch from origin',
          compact: true,
          enabled: true,
          onTap: () => taps++,
        ),
      ),
    );

    expect(find.text('Fetch'), findsNothing);
    await tester.tap(find.byTooltip('Fetch from origin'));
    expect(taps, 1);
  });

  testWidgets('regular toolbar action keeps its visible label', (tester) async {
    await tester.pumpWidget(
      _host(
        ToolbarButton(
          icon: Icons.cloud_download_outlined,
          label: 'Fetch',
          enabled: true,
          onTap: () {},
        ),
      ),
    );

    expect(find.text('Fetch'), findsOneWidget);
  });

  testWidgets('compact dropdown stays available with an icon tooltip', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        ToolbarDropdownButton(
          icon: Icons.account_tree_outlined,
          label: 'Branch',
          compact: true,
          enabled: true,
          onTap: () => taps++,
        ),
      ),
    );

    expect(find.text('Branch'), findsNothing);
    await tester.tap(find.byTooltip('Branch'));
    expect(taps, 1);
  });
}
