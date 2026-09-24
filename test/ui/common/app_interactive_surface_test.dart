import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
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
  test('resolves the shared layers and preserves a domain foreground', () {
    final palette = AppPalette.dark();
    const domain = Colors.orange;
    final normal = AppInteractiveSurface.resolve(
      palette,
      const {},
      foregroundColor: domain,
    );
    final hover = AppInteractiveSurface.resolve(
      palette,
      {WidgetState.hovered},
      foregroundColor: domain,
    );
    final pressed = AppInteractiveSurface.resolve(
      palette,
      {WidgetState.pressed},
    );
    final focused = AppInteractiveSurface.resolve(
      palette,
      {WidgetState.focused},
    );
    final selectedHover = AppInteractiveSurface.resolve(
      palette,
      {WidgetState.hovered, WidgetState.selected},
    );
    final disabled = AppInteractiveSurface.resolve(
      palette,
      {WidgetState.disabled},
    );

    expect(normal.foreground, domain);
    expect(hover.background, palette.interactionHover);
    expect(hover.foreground, domain);
    expect(pressed.background, palette.interactionPressed);
    expect(focused.border, palette.interactionFocusRing);
    expect(selectedHover.background, palette.interactionSelectedHover);
    expect(disabled.foreground, palette.interactionDisabledForeground);
    expect(disabled.opacity, palette.interactionDisabledOpacity);
  });

  testWidgets('surface activates by Space and Enter and exposes semantics', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        AppInteractiveSurface(
          onTap: () => taps++,
          semanticLabel: 'Action',
          tooltip: 'Action tooltip',
          autofocus: true,
          child: (context, visual) =>
              Text('Action', style: TextStyle(color: visual.foreground)),
        ),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Action tooltip'), findsOneWidget);
    final semantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == 'Action',
      ),
    );
    expect(semantics.properties.button, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(taps, 2);
  });

  testWidgets('disabled surface stays visible but cannot activate', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        AppInteractiveSurface(
          onTap: null,
          semanticLabel: 'Unavailable',
          child: (context, visual) =>
              Text('Unavailable', style: TextStyle(color: visual.foreground)),
        ),
      ),
    );
    final inkWell = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkWell.onTap, isNull);
    expect(inkWell.canRequestFocus, isFalse);
    final semantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Unavailable',
      ),
    );
    expect(semantics.properties.enabled, isFalse);
  });

  testWidgets('AppButton keeps its intrinsic width inside a column', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 400,
          child: Column(
            children: [AppButton(label: 'Open', onPressed: () {})],
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(AppButton)).width, lessThan(200));
  });
}
