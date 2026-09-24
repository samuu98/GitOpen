import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Opens the dialog and returns its future inside a record, so the caller's
/// `await` does NOT flatten/await the dialog future itself (which only
/// completes once the user picks an action).
Future<({Future<bool> result})> _open(
  WidgetTester tester, {
  required String title,
  required String body,
  String? confirmLabel,
  bool dangerous = false,
}) async {
  late Future<bool> result;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        extensions: [
          AppPalette.dark(),
          const AppSpacing.desktop(),
          const AppRadii.desktop(),
          const AppTypography.desktop(),
          const AppMotion.standard(),
        ],
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => result = ConfirmDialog.show(
                context,
                title: title,
                body: body,
                confirmLabel: confirmLabel,
                dangerous: dangerous,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return (result: result);
}

void main() {
  testWidgets('dangerous confirmation shows the question title and danger '
      'button', (tester) async {
    await _open(
      tester,
      title: 'Delete branch?',
      body: '"feature" will be deleted. This cannot be undone.',
      confirmLabel: 'Delete',
      dangerous: true,
    );

    expect(find.text('Delete branch?'), findsOneWidget);
    expect(
      find.text('"feature" will be deleted. This cannot be undone.'),
      findsOneWidget,
    );
    final danger = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Delete'),
    );
    expect(danger.kind, AppButtonKind.danger);
  });

  testWidgets('dangerous confirmation focuses Cancel, not the destructive '
      'action', (tester) async {
    final h = await _open(
      tester,
      title: 'Drop stash?',
      body: '"stash@{0}" will be dropped. This cannot be undone.',
      confirmLabel: 'Drop',
      dangerous: true,
    );

    // Enter activates the focused control; the safe choice must win.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(await h.result, isFalse);
  });

  testWidgets('non-dangerous confirmation focuses the primary action', (
    tester,
  ) async {
    final h = await _open(
      tester,
      title: 'Pull from origin?',
      body:
          'This merges the latest changes from origin into the current '
          'branch.',
      confirmLabel: 'Pull',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(await h.result, isTrue);
  });

  testWidgets('tapping the destructive action returns true', (tester) async {
    final h = await _open(
      tester,
      title: 'Remove worktree?',
      body: 'The worktree will be removed.',
      confirmLabel: 'Remove',
      dangerous: true,
    );

    await tester.tap(find.widgetWithText(AppButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(await h.result, isTrue);
  });

  testWidgets('tapping Cancel returns false', (tester) async {
    final h = await _open(
      tester,
      title: 'Remove remote?',
      body: 'The remote will be removed.',
      confirmLabel: 'Remove',
      dangerous: true,
    );

    await tester.tap(find.widgetWithText(AppButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(await h.result, isFalse);
  });

  testWidgets('Escape cancels the dialog', (tester) async {
    final h = await _open(
      tester,
      title: 'Delete tag?',
      body: 'The tag will be deleted.',
      confirmLabel: 'Delete',
      dangerous: true,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ConfirmDialog), findsNothing);
    expect(await h.result, isFalse);
  });
}
