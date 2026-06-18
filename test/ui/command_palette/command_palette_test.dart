import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/command_palette/command_palette.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

Widget _host() {
  return ProviderScope(
    child: MaterialApp(
      theme: ThemeData(extensions: [AppPalette.dark()]),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => CommandPalette.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('command palette filters commands and shows an empty state',
      (tester) async {
    await tester.pumpWidget(_host());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // With no active repo, only the always-available command is listed.
    expect(find.text('Open settings'), findsOneWidget);

    // A query that matches nothing shows the empty state.
    await tester.enterText(find.byType(TextField), 'zzzzz');
    await tester.pump();
    expect(find.text('No matching commands'), findsOneWidget);
    expect(find.text('Open settings'), findsNothing);

    // Narrowing back to a matching query restores the command.
    await tester.enterText(find.byType(TextField), 'settings');
    await tester.pump();
    expect(find.text('Open settings'), findsOneWidget);
  });
}
