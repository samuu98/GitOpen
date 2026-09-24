import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/ui/common/app_panel_state.dart';
import 'package:gitopen/ui/common/skeleton.dart';
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
  home: Scaffold(
    body: SizedBox(width: 240, height: 320, child: child),
  ),
);

void main() {
  testWidgets('list loading keeps the skeleton silhouette', (tester) async {
    await tester.pumpWidget(_host(const AppLoadingState.list()));
    await tester.pump();
    expect(find.byType(SkeletonList), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'detail loading is one compact centered indicator sized from tokens',
    (tester) async {
      await tester.pumpWidget(_host(const AppLoadingState.detail()));
      await tester.pump();
      expect(find.byType(SkeletonList), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final size = tester.getSize(find.byType(CircularProgressIndicator));
      expect(size.width, const AppSpacing.desktop().detailIndicatorSize);
      expect(size.height, const AppSpacing.desktop().detailIndicatorSize);
    },
  );

  testWidgets("error state shows a message, git's detail and a Retry "
      'action', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _host(
        AppErrorState(
          message: 'Could not load the diff',
          detail: 'fatal: bad object HEAD',
          onRetry: () => retries++,
        ),
      ),
    );

    expect(find.text('Could not load the diff'), findsOneWidget);
    expect(find.text('fatal: bad object HEAD'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('error state omits detail and retry when neither is given', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const AppErrorState(message: 'Could not load the diff')),
    );

    expect(find.text('Could not load the diff'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });
}
