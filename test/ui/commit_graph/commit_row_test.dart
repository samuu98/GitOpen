import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/commit_graph/commit_node.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/commits/commit_signature.dart';
import 'package:gitopen/ui/commit_graph/commit_row.dart';
import 'package:gitopen/ui/commit_graph/ref_decoration.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

CommitNode _node({String summary = 'Fix crash'}) {
  final sig = CommitSignature('Alice', 'a@x.io', DateTime(2026, 6, 10, 12));
  return CommitNode(
    commit: CommitInfo(
      sha: CommitSha('a' * 40),
      parentShas: const [],
      author: sig,
      committer: sig,
      summary: summary,
      message: '$summary\n\nbody',
    ),
    lane: 0,
    color: 0,
    topSegments: const [],
    bottomSegments: const [],
  );
}

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData(extensions: [AppPalette.dark()]),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('renders sha, summary and author', (tester) async {
    await tester.pumpWidget(
      _host(
        CommitRow(
          node: _node(),
          maxLane: 0,
          refs: const [],
          isSelected: false,
          onTap: () {},
        ),
      ),
    );
    expect(find.text('aaaaaaa'), findsOneWidget);
    expect(find.textContaining('Fix crash'), findsOneWidget);
    expect(find.textContaining('Alice'), findsOneWidget);
  });

  testWidgets('tap fires onTap; semantics reflects selection', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        CommitRow(
          node: _node(),
          maxLane: 0,
          refs: const [],
          isSelected: true,
          onTap: () => taps++,
        ),
      ),
    );
    await tester.tap(find.byType(InkWell).first);
    expect(taps, 1);

    final semantics = tester.getSemantics(
      find.bySemanticsLabel(RegExp('Commit aaaaaaa.*Fix crash.*Alice')),
    );
    expect(semantics.flagsCollection.isSelected, Tristate.isTrue);
  });

  testWidgets('ref pill renders and double-tap reports the ref', (
    tester,
  ) async {
    const ref = RefDecoration(
      name: 'origin/main',
      isRemote: true,
      isTag: false,
      isCurrent: false,
    );
    RefDecoration? doubleTapped;
    await tester.pumpWidget(
      _host(
        CommitRow(
          node: _node(),
          maxLane: 0,
          refs: const [ref],
          isSelected: false,
          onTap: () {},
          onRefDoubleTap: (r) => doubleTapped = r,
        ),
      ),
    );
    final pill = find.textContaining('origin/main');
    expect(pill, findsOneWidget);
    await tester.tap(pill);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(doubleTapped?.name, 'origin/main');
  });

  testWidgets('secondary tap reports a global position', (tester) async {
    Offset? pos;
    await tester.pumpWidget(
      _host(
        CommitRow(
          node: _node(),
          maxLane: 0,
          refs: const [],
          isSelected: false,
          onTap: () {},
          onSecondaryTap: (p) => pos = p,
        ),
      ),
    );
    await tester.tap(
      find.byType(InkWell).first,
      buttons: kSecondaryButton,
    );
    await tester.pump();
    expect(pos, isNotNull);
  });

  testWidgets('row keeps hoverable button semantics after polish', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        CommitRow(
          node: _node(),
          maxLane: 0,
          refs: const [],
          isSelected: false,
          onTap: () {},
        ),
      ),
    );

    final semantics = tester.getSemantics(
      find.bySemanticsLabel(RegExp('Commit aaaaaaa.*Fix crash.*Alice')),
    );
    expect(semantics.flagsCollection.isButton, isTrue);

    final row = find.byType(CommitRow);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(row));
    addTearDown(gesture.removePointer);
    await tester.pumpAndSettle();
    expect(find.textContaining('Fix crash'), findsOneWidget);
  });
}
