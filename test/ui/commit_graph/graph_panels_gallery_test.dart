import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/commit_graph/commit_node.dart';
import 'package:gitopen/application/git/bisect_state.dart';
import 'package:gitopen/application/git_lfs/git_lfs_models.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/commits/commit_signature.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/ui/bottom_panel/bottom_panel.dart';
import 'package:gitopen/ui/commit_graph/bisect_banner.dart';
import 'package:gitopen/ui/commit_graph/commit_row.dart';
import 'package:gitopen/ui/commit_graph/ref_decoration.dart';
import 'package:gitopen/ui/common/app_panel_state.dart';
import 'package:gitopen/ui/shell/view_selector.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

import '../../_helpers/screenshot.dart';

final _screenshots = PipelineScreenshotComparator('ux-l5-graph-panels');

Widget _cell(String title, Widget child, AppPalette palette) => SizedBox(
  width: 450,
  height: 210,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(title, style: TextStyle(color: palette.fg0)),
      Expanded(
        child: ColoredBox(color: palette.bg1, child: child),
      ),
    ],
  ),
);

Widget _gallery(AppPalette palette, RepoLocation repo, Key key) {
  final signature = CommitSignature('Ada', 'ada@example.com', DateTime(2026));
  final sha = CommitSha('a' * 40);
  final node = CommitNode(
    commit: CommitInfo(
      sha: sha,
      parentShas: const [],
      author: signature,
      committer: signature,
      summary: 'Improve graph interaction',
      message: 'Improve graph interaction',
    ),
    lane: 0,
    color: 0,
    topSegments: const [],
    bottomSegments: const [],
  );
  final bisect = BisectState(
    candidate: sha,
    subject: 'Improve graph interaction',
    good: [CommitSha('b' * 40)],
    bad: CommitSha('c' * 40),
    stepsLeft: 1,
  );
  return ProviderScope(
    overrides: [
      repoStatusProvider(repo).overrideWith(
        (_) async => const RepoStatus(
          isDetached: false,
          isBare: false,
          currentBranch: 'main',
          entries: [],
        ),
      ),
      githubSlugProvider(repo).overrideWith((_) async => null),
      gitLfsStatusProvider(repo).overrideWith(
        (_) async => const GitLfsStatus(
          isInstalled: false,
          version: null,
          isRepoConfigured: false,
          hasAttributes: false,
        ),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(
        fontFamily: 'Roboto',
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
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Graph row and ref pills',
                    style: TextStyle(color: palette.fg0),
                  ),
                  SizedBox(
                    width: 950,
                    child: CommitRow(
                      node: node,
                      maxLane: 0,
                      refs: const [
                        RefDecoration(
                          name: 'main',
                          isRemote: false,
                          isTag: false,
                          isCurrent: true,
                        ),
                        RefDecoration(
                          name: 'v1.2.3',
                          isRemote: false,
                          isTag: true,
                          isCurrent: false,
                        ),
                      ],
                      isSelected: true,
                      onTap: () {},
                      onRefTap: (_) {},
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('View selector', style: TextStyle(color: palette.fg0)),
                  SizedBox(width: 950, child: ViewSelector(repo: repo)),
                  const SizedBox(height: 20),
                  Text('Bottom tabs', style: TextStyle(color: palette.fg0)),
                  SizedBox(
                    width: 950,
                    height: 150,
                    child: BottomPanel(repo: repo),
                  ),
                  const SizedBox(height: 20),
                  for (final title in ['Commit details', 'Diff', 'File tree'])
                    Row(
                      children: [
                        _cell(
                          '$title loading',
                          const AppLoadingState.detail(),
                          palette,
                        ),
                        const SizedBox(width: 16),
                        _cell(
                          '$title error',
                          AppErrorState(
                            message: 'Failed to load ${title.toLowerCase()}',
                            detail: 'fatal: bad object HEAD',
                            onRetry: () {},
                          ),
                          palette,
                        ),
                      ],
                    ),
                  const SizedBox(height: 20),
                  Text('Bisect running', style: TextStyle(color: palette.fg0)),
                  BisectBanner(
                    state: bisect,
                    onAction: (_) async => null,
                    onSelect: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(loadAppFonts);
  for (final (name, palette) in [
    ('dark', AppPalette.dark()),
    ('light', AppPalette.light()),
  ]) {
    testWidgets('renders $name graph and panel gallery', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1300));
      final previous = goldenFileComparator;
      goldenFileComparator = _screenshots;
      addTearDown(() => goldenFileComparator = previous);
      final key = GlobalKey();
      final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
      await tester.pumpWidget(_gallery(palette, repo, key));
      await tester.pump(const Duration(milliseconds: 200));
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('graph_panels_$name.png'),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(find.text('main')));
      await tester.pump(const Duration(milliseconds: 200));
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('graph_pill_hover_$name.png'),
      );
      await mouse.moveTo(const Offset(990, 1250));
      Focus.of(tester.element(find.text('v1.2.3'))).requestFocus();
      await tester.pump(const Duration(milliseconds: 200));
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('graph_pill_focus_$name.png'),
      );
      await mouse.moveTo(tester.getCenter(find.text('Changes').first));
      await tester.pump(const Duration(milliseconds: 200));
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('view_selector_hover_$name.png'),
      );
      await mouse.moveTo(const Offset(990, 1250));
      Focus.of(tester.element(find.text('Changes').first)).requestFocus();
      await tester.pump(const Duration(milliseconds: 200));
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('view_selector_focus_$name.png'),
      );
    });
  }
}
