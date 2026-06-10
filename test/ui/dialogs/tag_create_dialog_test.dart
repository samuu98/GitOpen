import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/dialogs/tag_create_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  /// Pumps a host app whose button opens the dialog, assigning the dialog's
  /// result to the returned holder when it eventually closes.
  Future<List<TagCreateRequest?>> openDialog(WidgetTester tester) async {
    final resultHolder = <TagCreateRequest?>[null];
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [AppPalette.dark()]),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async =>
                resultHolder[0] = await TagCreateDialog.show(context),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle(); // dialog is now open
    return resultHolder;
  }

  testWidgets('returns name + message for an annotated tag', (tester) async {
    final result = await openDialog(tester);
    await tester.enterText(find.byType(TextField).first, ' v1.0 ');
    await tester.enterText(find.byType(TextField).last, ' first release ');
    await tester.tap(find.text('Create tag'));
    await tester.pumpAndSettle(); // dialog closed → onPressed resumed
    expect(result[0]?.name, 'v1.0');
    expect(result[0]?.message, 'first release');
  });

  testWidgets('empty message yields a lightweight request', (tester) async {
    final result = await openDialog(tester);
    await tester.enterText(find.byType(TextField).first, 'v1.1');
    await tester.tap(find.text('Create tag'));
    await tester.pumpAndSettle();
    expect(result[0]?.name, 'v1.1');
    expect(result[0]?.message, isNull);
  });
}
