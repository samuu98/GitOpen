import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/workspaces/repository_registry.dart';
import 'package:gitopen/application/workspaces/workspace_manager.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/refs/remote.dart';
import 'package:gitopen/domain/refs/stash.dart';
import 'package:gitopen/domain/refs/submodule.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/refs/worktree.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/sidebar/sidebar.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

import '../../_helpers/repository_validator.dart';

/// Whole-sidebar layout assertions: every label in the panel must start in the
/// same column, and a remote must not repeat its own name as a folder.
class _Fake implements GitReadOperations {
  static Branch _b(String name, {required bool remote, bool current = false}) =>
      Branch(
        name: name,
        fullName: remote ? 'refs/remotes/$name' : 'refs/heads/$name',
        isRemote: remote,
        isCurrent: current,
        tipSha: CommitSha('aaaaaaaa'),
        ahead: 0,
        behind: 0,
      );

  static final localBranch = _b('develop', remote: false, current: true);

  /// Exactly what `getRemotes` returns: branch names include the remote.
  static final originBranches = [
    _b('origin/main', remote: true),
    _b('origin/feature/login', remote: true),
  ];

  @override
  Future<List<Branch>> getLocalBranches(RepoLocation repo) async =>
      [localBranch];
  @override
  Future<List<Branch>> getRemoteBranches(RepoLocation repo) async =>
      originBranches;
  @override
  Future<List<Branch>> getBranches(RepoLocation repo) async => [
        localBranch,
        ...originBranches,
      ];
  @override
  Future<List<Tag>> getTags(RepoLocation repo) async => const [];
  @override
  Future<List<Remote>> getRemotes(RepoLocation repo) async => [
        Remote(
          name: 'origin',
          url: 'https://github.com/o/r.git',
          branches: originBranches,
        ),
      ];
  @override
  Future<List<Stash>> getStashes(RepoLocation repo) async => const [];
  @override
  Future<List<Submodule>> getSubmodules(RepoLocation repo) async => const [];
  @override
  Future<List<Worktree>> getWorktrees(RepoLocation repo) async => const [
        // Same path as the repo, so the row renders its current-checkout
        // tick. The branch is deliberately longer than the panel — that is
        // what used to starve the folder name to zero width — and is not
        // "develop" so the local branch row stays unambiguous below.
        Worktree(
          path: '/workspace-main',
          branch: 'feature/a-very-long-branch-name-wider-than-the-sidebar',
        ),
      ];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

class _FakeRegistry implements RepositoryRegistry {
  _FakeRegistry(this._repo);
  final RepoLocation _repo;

  @override
  Future<RepoLocation> add(String path) async => _repo;
  @override
  Future<void> touchLastOpened(RepoId id) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

/// Left edge of a text's painted box in the sidebar's coordinate space.
double _labelLeft(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dx;

void main() {
  const repo = RepoLocation(RepoId('r'), '/workspace-main', 't');

  Future<void> pumpSidebar(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        gitReadOperationsProvider.overrideWithValue(_Fake()),
        activeWorkspaceIdProvider.overrideWith((ref) => repo.id),
        workspaceManagerProvider.overrideWith(
          (ref) => WorkspaceManager(
            _FakeRegistry(repo),
            const PassThroughRepositoryValidator(),
          ),
        ),
        branchDivergenceProvider(repo).overrideWith(
          (ref) async => const <String, ({int ahead, int behind})>{},
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(workspaceManagerProvider.notifier).open('/workspace-main');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: const Scaffold(
            body: SizedBox(width: 320, height: 900, child: Sidebar()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every top-level label starts in the same column',
      (tester) async {
    await pumpSidebar(tester);

    // Sections other than LOCAL BRANCHES start collapsed.
    await tester.tap(find.text('WORKTREES'));
    await tester.tap(find.text('SUBMODULES'));
    await tester.tap(find.text('REMOTES'));
    await tester.pumpAndSettle();

    final title = _labelLeft(tester, 'LOCAL BRANCHES');
    // Rows are children of their section header, so they sit one step in.
    final column = title + kSidebarIndentStep;

    // A glyph-less empty hint used to sit in the glyph column, ~18px left of
    // every other label — the reported "No submodules" misalignment.
    expect(
      _labelLeft(tester, 'No submodules'),
      moreOrLessEquals(column, epsilon: 0.5),
      reason: 'empty hint must line up with the rows of a filled section',
    );
    // A branch leaf carries a marker glyph, so only its label should line up.
    expect(
      _labelLeft(tester, 'develop'),
      moreOrLessEquals(column, epsilon: 0.5),
      reason: 'branch names share the label column',
    );
    // The remote header is a level-1 row, indented inside REMOTES.
    expect(
      _labelLeft(tester, 'origin'),
      moreOrLessEquals(column, epsilon: 0.5),
      reason: 'a remote nests inside its section, not level with its title',
    );
    expect(
      _labelLeft(tester, 'origin'),
      greaterThan(_labelLeft(tester, 'REMOTES')),
      reason: 'a remote is a child of the REMOTES header',
    );
    // A worktree row is glyph-led (it carries the current-checkout tick), so
    // its tick belongs in the glyph column and its name in the label column —
    // the tick must not drift away from the name it marks.
    expect(
      _labelLeft(tester, 'workspace-main'),
      moreOrLessEquals(column, epsilon: 0.5),
      reason: 'worktree name shares the label column',
    );
    // Both ticks on screen — the current branch's and the current worktree's
    // — must sit in the glyph column, one step left of the label they mark.
    final ticks = find.text('✓');
    expect(ticks, findsNWidgets(2));
    for (var i = 0; i < 2; i++) {
      expect(
        tester.getTopLeft(ticks.at(i)).dx,
        moreOrLessEquals(kSidebarRowGlyphIndent, epsilon: 0.5),
        reason: 'a current-checkout tick sits in the glyph column, so it '
            'stays next to its label instead of drifting away from it',
      );
    }
  });

  testWidgets('a worktree keeps its name next to the tick when the branch '
      'name is long', (tester) async {
    // A branch name longer than the panel used to take the whole row: the
    // trailing Text had no width constraint, so the Expanded holding the
    // worktree's folder name was squeezed to width 0. On screen that left a
    // lone tick followed by an overflowing branch name.
    await pumpSidebar(tester);
    await tester.tap(find.text('WORKTREES'));
    await tester.pumpAndSettle();

    final name = tester.getRect(find.text('workspace-main'));
    expect(
      name.width,
      greaterThan(0),
      reason: 'the worktree name must not be starved to zero width',
    );
    // Tick, then the name right next to it — one glyph column apart.
    expect(
      name.left - tester.getRect(find.text('✓').last).left,
      moreOrLessEquals(kSidebarGlyphColumnWidth + kSidebarGlyphGap,
          epsilon: 0.5,),
    );
  });

  testWidgets('a remote does not repeat its own name as a folder',
      (tester) async {
    await pumpSidebar(tester);
    await tester.tap(find.text('REMOTES'));
    await tester.pumpAndSettle();

    // "REMOTES > origin > origin > main" — the inner "origin" came from
    // BranchTree splitting the fully-qualified branch name.
    expect(
      find.text('origin'),
      findsOneWidget,
      reason: 'only the remote header itself may be labelled "origin"',
    );
    // Its branches still show, one level in, without the remote segment.
    expect(find.text('main'), findsOneWidget);
    expect(find.text('feature'), findsOneWidget);

    // A remote branch nests exactly one step past its remote header.
    final origin = _labelLeft(tester, 'origin');
    final main = _labelLeft(tester, 'main');
    expect(main, greaterThan(origin));
  });
}
