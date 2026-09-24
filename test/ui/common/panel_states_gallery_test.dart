import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/common/app_empty_state.dart';
import 'package:gitopen/ui/common/app_panel_state.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

import '../../_helpers/screenshot.dart';

const _cellWidth = 540.0;
const _cellHeight = 300.0;
const _labelHeight = 20.0;

Widget _cell(AppPalette palette, String label, Widget child) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: SizedBox(
      width: _cellWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: _labelHeight,
            child: Text(label, style: TextStyle(color: palette.fg0)),
          ),
          SizedBox(
            width: _cellWidth,
            height: _cellHeight,
            child: ColoredBox(color: palette.bg1, child: child),
          ),
        ],
      ),
    ),
  );
}

Widget _gallery(AppPalette palette, Key key, VoidCallback onRetry) {
  final cells = [
    _cell(palette, 'List loading', const AppLoadingState.list(rows: 4)),
    _cell(palette, 'Detail loading', const AppLoadingState.detail()),
    _cell(
      palette,
      'Empty',
      const AppEmptyState(
        icon: Icons.inbox_outlined,
        title: 'No open pull requests',
        message: 'This repository has no open pull requests right now.',
      ),
    ),
    _cell(
      palette,
      'Error with Retry',
      AppErrorState(
        message: 'Could not load the diff',
        detail: 'fatal: bad object HEAD',
        onRetry: onRetry,
      ),
    ),
    _cell(
      palette,
      'Confirm: delete branch',
      const ConfirmDialog(
        title: 'Delete branch?',
        body: '"feature" will be deleted. This cannot be undone.',
        confirmLabel: 'Delete',
        dangerous: true,
      ),
    ),
    _cell(
      palette,
      'Confirm: drop stash',
      const ConfirmDialog(
        title: 'Drop stash?',
        body: '"stash@{0}" will be dropped. This cannot be undone.',
        confirmLabel: 'Drop',
        dangerous: true,
      ),
    ),
  ];
  return MaterialApp(
    theme: ThemeData(
      fontFamily: 'Roboto',
      brightness: palette.bg0.computeLuminance() < 0.5
          ? Brightness.dark
          : Brightness.light,
      extensions: [
        palette,
        const AppSpacing.desktop(),
        const AppRadii.desktop(),
        const AppTypography.desktop(),
        const AppMotion.standard(),
      ],
    ),
    home: Scaffold(
      backgroundColor: palette.bg0,
      body: RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: palette.bg0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: cells,
            ),
          ),
        ),
      ),
    ),
  );
}

final _screenshots = PipelineScreenshotComparator('ux-l3-states-copy');

void main() {
  setUpAll(loadAppFonts);
  for (final (name, palette) in [
    ('dark', AppPalette.dark()),
    ('light', AppPalette.light()),
  ]) {
    testWidgets('renders $name panel states and confirmation gallery', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 2100));
      final previousComparator = goldenFileComparator;
      goldenFileComparator = _screenshots;
      addTearDown(() => goldenFileComparator = previousComparator);
      var retries = 0;
      final key = GlobalKey();
      await tester.pumpWidget(_gallery(palette, key, () => retries++));
      await tester.pump(const Duration(milliseconds: 180));

      // Structure, not pixels: the panel states render their finders...
      expect(find.byType(AppLoadingState), findsNWidgets(2));
      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.byType(ConfirmDialog), findsNWidgets(2));

      // ...the error state's Retry action fires its callback...
      await tester.tap(find.text('Retry'));
      expect(retries, 1);

      // ...and both destructive confirmations focus Cancel, not the
      // destructive action.
      for (final cancel in tester.widgetList<AppButton>(
        find.widgetWithText(AppButton, 'Cancel'),
      )) {
        expect(cancel.autofocus, isTrue);
      }
      for (final destructive in tester.widgetList<AppButton>(
        find.byWidgetPredicate(
          (w) => w is AppButton && w.kind == AppButtonKind.danger,
        ),
      )) {
        expect(destructive.autofocus, isFalse);
      }

      await expectLater(
        find.byKey(key),
        matchesGoldenFile('panel_states_gallery_$name.png'),
      );
      expect(
        _screenshots.fileFor('panel_states_gallery_$name.png').existsSync(),
        isTrue,
      );
    });
  }
}
