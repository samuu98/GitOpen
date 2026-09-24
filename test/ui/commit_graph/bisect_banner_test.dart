import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/bisect_state.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/ui/commit_graph/bisect_banner.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  testWidgets('running, found, and reset states', (tester) async {
    final candidate = CommitSha('a' * 40);
    final bad = CommitSha('b' * 40);
    final good = CommitSha('c' * 40);
    final pending = Completer<String?>();
    BisectAction? action;
    final running = BisectState(
      candidate: candidate,
      subject: 'suspect change',
      good: [good],
      bad: bad,
      stepsLeft: 2,
    );

    Widget host(BisectState state) => MaterialApp(
      theme: ThemeData(extensions: [AppPalette.dark()]),
      home: Scaffold(
        body: BisectBanner(
          state: state,
          onAction: (next) {
            action = next;
            return pending.future;
          },
          onSelect: (_) {},
        ),
      ),
    );

    await tester.pumpWidget(host(running));
    expect(find.textContaining('suspect change'), findsOneWidget);
    expect(find.textContaining('2 steps left'), findsOneWidget);
    await tester.tap(find.text('Good'));
    await tester.pump();
    expect(action, BisectAction.good);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Bad'))
          .onPressed,
      isNull,
    );
    pending.complete('Git could not classify this commit');
    await tester.pump();
    expect(find.text('Git could not classify this commit'), findsOneWidget);

    final found = BisectState(
      candidate: candidate,
      subject: 'suspect change',
      good: [good],
      bad: bad,
      stepsLeft: 0,
      firstBad: bad,
    );
    await tester.pumpWidget(host(found));
    expect(find.textContaining('First bad commit'), findsOneWidget);
    expect(find.text('Select in graph'), findsOneWidget);
    expect(find.text('Good'), findsNothing);
    await tester.tap(find.text('Reset'));
    await tester.pump();
    expect(action, BisectAction.reset);
  });
}
