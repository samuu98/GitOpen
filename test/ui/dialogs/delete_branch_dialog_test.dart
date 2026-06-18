import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/branch_deletion.dart';
import 'package:gitopen/ui/dialogs/delete_branch_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Opens the dialog and returns its future inside a record, so the caller's
/// `await` does NOT flatten/await the dialog future itself (which only
/// completes once the user taps an action).
Future<({Future<DeleteBranchSelection?> dialog})> _open(
  WidgetTester tester,
  BranchDeletionTargets targets,
) async {
  late Future<DeleteBranchSelection?> dialog;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: [AppPalette.dark()]),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () =>
                  dialog = DeleteBranchDialog.show(context, targets: targets),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return (dialog: dialog);
}

void main() {
  testWidgets('shows both sides and returns both selected by default',
      (tester) async {
    final h = await _open(
      tester,
      const BranchDeletionTargets(
        localName: 'feature',
        remoteRef: 'origin/feature',
      ),
    );
    expect(find.text('Local branch feature'), findsOneWidget);
    expect(find.text('Remote branch origin/feature'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    final sel = await h.dialog;
    expect(sel!.deleteLocal, isTrue);
    expect(sel.deleteRemote, isTrue);
  });

  testWidgets('current local branch cannot be selected', (tester) async {
    final h = await _open(
      tester,
      const BranchDeletionTargets(
        localName: 'main',
        localIsCurrent: true,
        remoteRef: 'origin/main',
      ),
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    final sel = await h.dialog;
    expect(sel!.deleteLocal, isFalse); // disabled -> not selected
    expect(sel.deleteRemote, isTrue);
  });

  testWidgets('only the remote side when there is no local', (tester) async {
    final h = await _open(
      tester,
      const BranchDeletionTargets(remoteRef: 'origin/feature'),
    );
    expect(find.textContaining('Local branch'), findsNothing);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    final sel = await h.dialog;
    expect(sel!.deleteLocal, isFalse);
    expect(sel.deleteRemote, isTrue);
  });
}
