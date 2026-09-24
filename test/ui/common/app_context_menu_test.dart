import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/common/app_context_menu.dart';
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
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('menu button resolves shared hover, press and selected colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(AppMenuButton(label: 'Open', onPressed: () {}, selected: true)),
    );
    final palette = AppPalette.dark();
    final button = tester.widget<MenuItemButton>(find.byType(MenuItemButton));
    final background = button.style!.backgroundColor!;
    expect(
      background.resolve({WidgetState.selected}),
      palette.interactionSelected,
    );
    expect(
      background.resolve({WidgetState.hovered}),
      palette.interactionSelectedHover,
    );
    expect(
      background.resolve({WidgetState.pressed}),
      Color.lerp(palette.interactionSelected, palette.interactionPressed, 0.25),
    );
    expect(
      button.style!.minimumSize!.resolve({})!.height,
      const AppSpacing.desktop().menuRowHeight,
    );
  });

  testWidgets('popup item uses the context menu row height', (tester) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () {
              unawaited(
                AppContextMenu.show<int>(
                  context,
                  globalPosition: const Offset(100, 100),
                  entries: const [AppMenuItem(value: 1, label: 'Open')],
                ),
              );
            },
            child: const Text('Show menu'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Show menu'));
    await tester.pumpAndSettle();
    final item = tester.widget<PopupMenuItem<int>>(
      find.byWidgetPredicate((widget) => widget is PopupMenuItem<int>),
    );
    expect(find.byType(AppContextMenuRow), findsOneWidget);
    expect(item.height, const AppSpacing.desktop().menuRowHeight);
    expect(
      Theme.of(tester.element(find.text('Open'))).hoverColor,
      AppPalette.dark().interactionHover,
    );
  });
}
