import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
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
  testWidgets(
    'toolbar states and shortcut tooltip use the shared surface',
    (tester) async {
      await tester.pumpWidget(
        _host(
          ToolbarButton(
            icon: Icons.cloud_download_outlined,
            label: 'Fetch',
            tooltip: 'Fetch (F5)',
            enabled: false,
            onTap: () {},
          ),
        ),
      );
      var surface = tester.widget<AppInteractiveSurface>(
        find.byType(AppInteractiveSurface),
      );
      expect(surface.onTap, isNull);
      expect(surface.height, 38);
      expect(find.byTooltip('Fetch (F5)'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          ToolbarButton(
            icon: Icons.cloud_download_outlined,
            label: 'Fetch',
            tooltip: 'Fetch (F5)',
            enabled: true,
            onTap: () {},
          ),
        ),
      );
      surface = tester.widget<AppInteractiveSurface>(
        find.byType(AppInteractiveSurface),
      );
      expect(surface.onTap, isNotNull);
      await tester.ensureVisible(find.text('Fetch'));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer();
      await gesture.moveTo(tester.getCenter(find.text('Fetch')));
      await tester.pumpAndSettle();
      final hovered = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(
        (hovered.decoration! as BoxDecoration).color,
        AppPalette.dark().interactionHover,
      );
      expect(
        tester.widget<InkWell>(find.byType(InkWell)).hoverColor,
        Colors.transparent,
      );
      await gesture.removePointer();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final focused = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(
        (focused.decoration! as BoxDecoration).border!.top.color,
        AppPalette.dark().interactionFocusRing,
      );
    },
  );
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
