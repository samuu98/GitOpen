import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
  testWidgets('exposes button semantics and activates from the keyboard', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(
      _host(
        AppButton.primary(
          label: 'Save changes',
          autofocus: true,
          onPressed: () => presses++,
        ),
      ),
    );
    await tester.pump();

    final semantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Save changes',
      ),
    );
    expect(semantics.properties.button, isTrue);
    expect(semantics.properties.enabled, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 1);
  });

  testWidgets('disabled button is not focusable or actionable', (tester) async {
    await tester.pumpWidget(
      _host(
        const AppButton.primary(label: 'Save changes', onPressed: null),
      ),
    );

    final semantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == 'Save changes',
      ),
    );
    expect(semantics.properties.enabled, isFalse);
    final inkWell = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkWell.canRequestFocus, isFalse);
    expect(inkWell.onTap, isNull);
    await tester.tap(find.text('Save changes'));
  });
}
