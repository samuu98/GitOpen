import 'dart:ui' show Tristate;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/commit_graph/commit_node.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/commits/commit_signature.dart';
import 'package:gitopen/ui/commit_graph/commit_row.dart';
import 'package:gitopen/ui/commit_graph/ref_decoration.dart';
import 'package:gitopen/ui/commit_graph/ref_pill.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:intl/intl.dart';

Widget _host(
  Widget child, {
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: ThemeData(extensions: [AppPalette.dark()]),
      home: Scaffold(
        body: SizedBox(width: 900, height: 320, child: child),
      ),
    ),
  );
}

CommitInfo _commit() {
  final author = CommitSignature(
    'Ada',
    'ada@example.com',
    DateTime.utc(2026, 6, 10, 12, 30),
  );
  return CommitInfo(
    sha: CommitSha('abcdef1234567890'),
    parentShas: const [],
    author: author,
    committer: author,
    summary: 'Fix cache invalidation',
    message: 'Fix cache invalidation',
  );
}

void main() {
  testWidgets(
    'CommitRow renders metadata, handles tap, and exposes semantics',
    (tester) async {
      var tapped = 0;
      final commit = _commit();
      final node = CommitNode(
        commit: commit,
        lane: 0,
        color: 0,
        topSegments: const [],
        bottomSegments: const [],
      );
      final date = DateFormat(
        'yyyy-MM-dd HH:mm',
      ).format(commit.author.when.toLocal());
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _host(
          CommitRow(
            node: node,
            maxLane: 0,
            refs: const [
              RefDecoration(
                name: 'main',
                isRemote: false,
                isTag: false,
                isCurrent: true,
              ),
            ],
            isSelected: true,
            onTap: () => tapped++,
          ),
        ),
      );

      expect(find.text('Fix cache invalidation'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('main'), findsOneWidget);
      final semanticsNode = tester.getSemantics(find.byType(CommitRow));
      expect(
        semanticsNode.label,
        contains(
          'Commit abcdef1, Fix cache invalidation, by Ada, $date, refs main',
        ),
      );
      expect(semanticsNode.flagsCollection.isButton, isTrue);
      expect(semanticsNode.flagsCollection.isSelected, Tristate.isTrue);

      await tester.tap(find.text('Fix cache invalidation'));
      expect(tapped, 1);
      semantics.dispose();
    },
  );

  testWidgets('ref pill preserves branch and remote labels', (tester) async {
    const decoration = RefDecoration(
      name: 'main',
      syncedRemotes: ['origin/main'],
      isRemote: false,
      isTag: false,
      isCurrent: true,
    );
    await tester.pumpWidget(_host(const RefPill(decoration: decoration)));

    expect(find.text('main'), findsOneWidget);
    expect(find.text('origin/main'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('double-click-only ref pill ignores a single click', (
    tester,
  ) async {
    const decoration = RefDecoration(
      name: 'feature/login',
      isRemote: false,
      isTag: false,
      isCurrent: false,
    );
    var doubleTaps = 0;
    await tester.pumpWidget(
      _host(RefPill(decoration: decoration, onDoubleTap: () => doubleTaps++)),
    );
    expect(
      find.byTooltip('Double-click to check out branch feature/login'),
      findsOneWidget,
    );
    await tester.tap(find.text('feature/login'));
    await tester.pumpAndSettle();
    expect(doubleTaps, 0);
  });

  testWidgets('clickable ref pill has shared focus and named action tooltip', (
    tester,
  ) async {
    const decoration = RefDecoration(
      name: 'feature/login',
      isRemote: false,
      isTag: false,
      isCurrent: false,
    );
    await tester.pumpWidget(
      _host(RefPill(decoration: decoration, onTap: () {})),
    );
    expect(find.byType(AppInteractiveSurface), findsOneWidget);
    expect(find.byTooltip('Select branch feature/login'), findsOneWidget);
    final surface = find.byType(AppInteractiveSurface);
    final container = find
        .descendant(
          of: surface,
          matching: find.byType(AnimatedContainer),
        )
        .first;
    final base =
        (tester.widget<AnimatedContainer>(container).decoration!
                as BoxDecoration)
            .color;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(
      location: tester.getCenter(find.text('feature/login')),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      (tester.widget<AnimatedContainer>(container).decoration! as BoxDecoration)
          .color,
      isNot(base),
    );
    await mouse.moveTo(Offset.zero);
    Focus.of(tester.element(find.text('feature/login'))).requestFocus();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      (tester.widget<AnimatedContainer>(container).decoration! as BoxDecoration)
          .border!
          .top
          .color,
      AppPalette.dark().interactionFocusRing,
    );
  });
}
