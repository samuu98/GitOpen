import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/bisect_state.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings_notifier.dart';
import 'package:gitopen/application/settings/settings_store.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/refs/remote.dart';
import 'package:gitopen/domain/refs/stash.dart';
import 'package:gitopen/domain/refs/submodule.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/refs/worktree.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/commit_graph/bisect_banner.dart';
import 'package:gitopen/ui/sidebar/branch_tree.dart';
import 'package:gitopen/ui/sidebar/branch_tree_view.dart';
import 'package:gitopen/ui/sidebar/remotes_section.dart';
import 'package:gitopen/ui/sidebar/stash_row.dart';
import 'package:gitopen/ui/sidebar/submodule_row.dart';
import 'package:gitopen/ui/sidebar/tag_row.dart';
import 'package:gitopen/ui/sidebar/worktree_row.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/toolbar/toolbar_buttons.dart';

import '../../_helpers/screenshot.dart';

const _repo = RepoLocation(RepoId('ux-l4-gallery'), 'C:/repo', 'repo');
const _branch = Branch(
  name: 'main',
  fullName: 'refs/heads/main',
  isRemote: false,
  isCurrent: true,
  ahead: 0,
  behind: 0,
);
const _remote = Remote(
  name: 'origin',
  url: 'https://example.org/repo',
  branches: [],
);
final _submodule = Submodule(
  path: 'vendor/lib',
  sha: CommitSha('aaaa'),
  status: SubmoduleStatus.uninitialized,
);

class _SettingsStore implements SettingsStore {
  @override
  Future<Map<String, dynamic>> readAll() async => const {};
  @override
  Future<void> put(String key, dynamic value) async {}
}

void main() {
  setUpAll(loadAppFonts);
  final shots = PipelineScreenshotComparator('ux-l4-toolbar-sidebar');

  for (final dark in [true, false]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('toolbar and sidebar gallery $mode', (tester) async {
      final previous = goldenFileComparator;
      goldenFileComparator = shots;
      addTearDown(() => goldenFileComparator = previous);
      await tester.binding.setSurfaceSize(const Size(900, 680));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final palette = dark ? AppPalette.dark() : AppPalette.light();
      final container = ProviderContainer(
        overrides: [
          appSettingsProvider.overrideWith(
            (ref) => AppSettingsNotifier(_SettingsStore()),
          ),
          branchDivergenceProvider(_repo).overrideWith(
            (ref) async => const <String, ({int ahead, int behind})>{},
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: screenshotApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
              extensions: [
                palette,
                const AppSpacing.desktop(),
                const AppRadii.desktop(),
                const AppTypography.desktop(),
                const AppMotion.standard(),
              ],
            ),
            home: Scaffold(
              body: RepaintBoundary(
                key: const Key('gallery'),
                child: ColoredBox(
                  color: palette.bg2,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ToolbarButton(
                              icon: Icons.cloud_download_outlined,
                              label: 'Fetch',
                              tooltip: 'Fetch (F5)',
                              enabled: true,
                              onTap: () {},
                            ),
                            ToolbarDropdownButton(
                              icon: Icons.account_tree_outlined,
                              label: 'Branch',
                              enabled: true,
                              onTap: () {},
                            ),
                            ToolbarButton(
                              icon: Icons.north,
                              label: 'Push',
                              enabled: false,
                              onTap: () {},
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: 360,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('LOCAL BRANCHES'),
                              BranchTreeView(
                                nodes: BranchTree.build(const [_branch]),
                                repo: _repo,
                              ),
                              const Text('REMOTES'),
                              RemoteGroup(
                                remote: _remote,
                                repo: _repo,
                                onChanged: () {},
                              ),
                              const Text('TAGS'),
                              TagRow(
                                tag: Tag(
                                  name: 'v1.0',
                                  fullName: 'refs/tags/v1.0',
                                  targetSha: CommitSha('bbbb'),
                                  isAnnotated: false,
                                ),
                                repo: _repo,
                              ),
                              const Text('STASHES'),
                              StashRow(
                                stash: Stash(
                                  index: 0,
                                  sha: CommitSha('cccc'),
                                  message: 'Draft changes',
                                  createdAt: DateTime.utc(2026),
                                ),
                                repo: _repo,
                              ),
                              const Text('WORKTREES'),
                              const WorktreeRow(
                                worktree: Worktree(
                                  path: 'C:/feature',
                                  branch: 'feature',
                                ),
                                repo: _repo,
                              ),
                              const Text('SUBMODULES'),
                              SubmoduleRow(submodule: _submodule, repo: _repo),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> capture(String name) async {
        await expectLater(
          find.byKey(const Key('gallery')),
          matchesGoldenFile('${name}_$mode.png'),
        );
        expect(shots.fileFor('${name}_$mode.png').existsSync(), isTrue);
      }

      await capture('toolbar_default');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(find.text('Fetch')));
      await tester.pumpAndSettle();
      await capture('toolbar_hover');
      await mouse.moveTo(const Offset(880, 650));
      Focus.of(tester.element(find.text('Fetch'))).requestFocus();
      await tester.pumpAndSettle();
      await capture('toolbar_focus_disabled');

      for (final (section, label) in [
        ('branch', 'main'),
        ('remote', 'origin'),
        ('tag', 'v1.0'),
        ('stash', 'stash@{0}'),
        ('worktree', 'feature'),
        ('submodule', 'vendor/lib'),
      ]) {
        final target = find.textContaining(label).first;
        await mouse.moveTo(tester.getCenter(target));
        await tester.pumpAndSettle();
        await capture('sidebar_hover_$section');
        await mouse.moveTo(const Offset(880, 650));
        Focus.of(tester.element(target)).requestFocus();
        await tester.pumpAndSettle();
        await capture('sidebar_focus_$section');
      }
      await mouse.moveTo(tester.getCenter(find.byTooltip('Pin main')));
      await tester.pumpAndSettle();
      await capture('pin_hover');
      await mouse.moveTo(
        tester.getCenter(find.byTooltip('Hide main from the graph')),
      );
      await tester.pumpAndSettle();
      await capture('eye_hover');

      container
          .read(busyProvider.notifier)
          .begin('${_repo.id.value}/remote-remove:origin');
      await pumpUntilPending(tester, find.byType(CircularProgressIndicator));
      await capture('remote_remove_pending');
      container
          .read(busyProvider.notifier)
          .end('${_repo.id.value}/remote-remove:origin');
      // Past the busy indicator's minimum hold: the next capture then waits
      // for its own spinner, and no hold timer outlives the test.
      await tester.pumpAndSettle();
      container
          .read(busyProvider.notifier)
          .begin('${_repo.id.value}/submodule-update:vendor/lib');
      await pumpUntilPending(tester, find.byType(CircularProgressIndicator));
      await capture('submodule_update_pending');
      container
          .read(busyProvider.notifier)
          .end('${_repo.id.value}/submodule-update:vendor/lib');
      await tester.pumpAndSettle();
      await mouse.removePointer();
    });

    testWidgets('bisect banner gallery $mode', (tester) async {
      final previous = goldenFileComparator;
      goldenFileComparator = shots;
      addTearDown(() => goldenFileComparator = previous);
      await tester.binding.setSurfaceSize(const Size(900, 180));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final palette = dark ? AppPalette.dark() : AppPalette.light();
      final pending = Completer<String?>();
      await tester.pumpWidget(
        screenshotApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            extensions: [
              palette,
              const AppSpacing.desktop(),
              const AppRadii.desktop(),
              const AppTypography.desktop(),
            ],
          ),
          home: Scaffold(
            body: RepaintBoundary(
              key: const Key('banner'),
              child: ColoredBox(
                color: palette.bg2,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: BisectBanner(
                    state: BisectState(
                      candidate: CommitSha('aaaa'),
                      subject: 'Find the regression',
                      good: [CommitSha('bbbb')],
                      bad: CommitSha('cccc'),
                      stepsLeft: 2,
                    ),
                    onAction: (_) => pending.future,
                    onSelect: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Good'));
      await pumpUntilPending(tester, find.byType(CircularProgressIndicator));
      await expectLater(
        find.byKey(const Key('banner')),
        matchesGoldenFile('bisect_busy_$mode.png'),
      );
      pending.complete(null);
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const Key('banner')),
        matchesGoldenFile('bisect_after_$mode.png'),
      );
    });
  }
}
