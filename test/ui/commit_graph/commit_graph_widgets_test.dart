import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/commit_graph/commit_node.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/commits/commit_signature.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/commit_graph/commit_row.dart';
import 'package:gitopen/ui/commit_graph/local_changes_row.dart';
import 'package:gitopen/ui/commit_graph/ref_decoration.dart';
import 'package:gitopen/ui/commit_graph/ref_pill.dart';
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

  testWidgets('LocalChangesRow selects the working copy inline', (
    tester,
  ) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
    const status = RepoStatus(
      isDetached: false,
      isBare: false,
      currentBranch: 'main',
      entries: [
        WorkingFileEntry(
          path: 'lib/app.dart',
          indexState: WorkingFileState.unmodified,
          workingTreeState: WorkingFileState.modified,
        ),
      ],
    );

    await tester.pumpWidget(
      _host(
        Column(
          children: [
            LocalChangesRow(repo: repo),
            Consumer(
              builder: (_, ref, _) => Text(
                'selected:${ref.watch(localChangesSelectedProvider)}',
              ),
            ),
          ],
        ),
        overrides: [
          repoStatusProvider(repo).overrideWith((_) async => status),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('Local Changes (1)'), findsOneWidget);
    expect(find.text('selected:false'), findsOneWidget);

    await tester.tap(find.text('Local Changes (1)'));
    await tester.pump();

    expect(find.text('selected:true'), findsOneWidget);
  });

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
}
