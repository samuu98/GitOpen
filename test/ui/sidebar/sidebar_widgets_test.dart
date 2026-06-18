import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/refs/stash.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/sidebar/branch_tree.dart';
import 'package:gitopen/ui/sidebar/branch_tree_view.dart';
import 'package:gitopen/ui/sidebar/stash_row.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

Widget _host(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: ThemeData(extensions: [AppPalette.dark()]),
      home: Scaffold(
        body: SizedBox(width: 360, height: 320, child: child),
      ),
    ),
  );
}

Branch _branch(
  String name, {
  bool isCurrent = false,
  String sha = 'aaaaaaaa',
}) {
  return Branch(
    name: name,
    fullName: 'refs/heads/$name',
    isRemote: false,
    isCurrent: isCurrent,
    tipSha: CommitSha(sha),
    ahead: 0,
    behind: 0,
  );
}

void main() {
  testWidgets('BranchTreeView collapses folders and toggles visibility', (
    tester,
  ) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
    final nodes = BranchTree.build([
      _branch('main', isCurrent: true),
      _branch('feature/login', sha: 'bbbbbbbb'),
    ]);

    await tester.pumpWidget(
      _host(
        BranchTreeView(nodes: nodes, repo: repo),
        overrides: [
          branchDivergenceProvider(repo).overrideWith(
            (ref) async => const <String, ({int ahead, int behind})>{},
          ),
        ],
      ),
    );

    expect(find.text('main'), findsOneWidget);
    expect(find.text('feature'), findsOneWidget);
    expect(find.text('login'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Hide main from the graph'));
    await tester.pump();
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);

    await tester.tap(find.text('feature'));
    await tester.pump();
    expect(find.text('login'), findsNothing);
  });

  testWidgets('StashRow reveals its stash commit', (tester) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
    final sha = CommitSha('abcdef1234567890');
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _host(
        Column(
          children: [
            StashRow(
              stash: Stash(
                index: 0,
                sha: sha,
                message: 'WIP changes',
                createdAt: DateTime.utc(2026),
              ),
              repo: repo,
              onRefresh: () {},
            ),
            Consumer(
              builder: (_, ref, _) {
                final selected = ref.watch(selectedCommitShaProvider);
                return Text('selected:${selected?.short() ?? 'none'}');
              },
            ),
          ],
        ),
      ),
    );

    final node = tester.getSemantics(
      find.bySemanticsLabel('Stash 0: WIP changes'),
    );
    expect(node.flagsCollection.isButton, isTrue);
    expect(find.text('selected:none'), findsOneWidget);

    await tester.tap(find.textContaining('stash@{0}'));
    await tester.pump();

    expect(find.text('selected:abcdef1'), findsOneWidget);
    semantics.dispose();
  });
}
