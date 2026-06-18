import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/settings/sections/about_section.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

Future<void> _pump(WidgetTester tester, String version) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appVersionProvider.overrideWith((ref) async => version),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: const Scaffold(body: AboutSection()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the running version from package info', (tester) async {
    await _pump(tester, '1.5.1');
    expect(find.text('1.5.1'), findsOneWidget);
    expect(find.text('0.3.0-dev'), findsNothing);
  });
}
