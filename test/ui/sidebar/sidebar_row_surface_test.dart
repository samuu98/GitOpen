import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  testWidgets('sidebar row uses list density and shared interaction', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          extensions: [
            AppPalette.dark(),
            const AppSpacing.desktop(),
            const AppRadii.desktop(),
            const AppTypography.desktop(),
          ],
        ),
        home: Scaffold(
          body: SidebarRowSurface(
            onTap: () {},
            child: const Text('row'),
          ),
        ),
      ),
    );
    final surface = tester.widget<AppInteractiveSurface>(
      find.byType(AppInteractiveSurface),
    );
    expect(surface.height, 30);
    expect(surface.onTap, isNotNull);
  });
}
