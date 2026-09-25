import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/domain/diff/file_diff.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/theme/app_design_tokens.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/diff_preview_pane.dart';
import 'package:gitopen/ui/working_copy/file_row.dart';
import 'package:gitopen/ui/working_copy/hunk_row.dart';
import 'package:gitopen/ui/working_copy/working_copy_panel.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

import '../../_helpers/screenshot.dart';
import 'working_copy_screenshot_fonts.dart';

const _entry = WorkingFileEntry(
  path: 'lib/app.dart',
  indexState: WorkingFileState.unmodified,
  workingTreeState: WorkingFileState.modified,
);
const _hunk = DiffHunk(
  oldStart: 1,
  oldCount: 1,
  newStart: 1,
  newCount: 1,
  header: '@@ -1,1 +1,1 @@',
  lines: [
    DiffLine(kind: DiffLineKind.deletion, content: 'old', oldLine: 1),
    DiffLine(kind: DiffLineKind.addition, content: 'new', newLine: 1),
  ],
);
const _diff = FileDiff(
  path: 'lib/app.dart',
  changeKind: FileChangeKind.modified,
  isBinary: false,
  linesAdded: 1,
  linesDeleted: 1,
  hunks: [_hunk],
);
const _status = RepoStatus(
  isDetached: false,
  isBare: false,
  entries: [_entry],
);

class _Write implements GitWriteOperations {
  int calls = 0;
  @override
  Future<GitResult<void>> stageFiles(RepoLocation r, List<String> paths) async {
    calls++;
    return const GitSuccess(null);
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not faked');
}

void main() {
  setUpAll(loadWorkingCopyFonts);
  for (final (name, palette) in [
    ('dark', AppPalette.dark()),
    ('light', AppPalette.light()),
  ]) {
    testWidgets('$name working-copy states', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 550));
      final previousComparator = goldenFileComparator;
      final screenshots = PipelineScreenshotComparator('ux-l6-working-copy');
      goldenFileComparator = screenshots;
      addTearDown(() => goldenFileComparator = previousComparator);
      final repo = RepoLocation(RepoId.newId(), 'unused', 'test');
      final statusGate = Completer<RepoStatus>();
      final write = _Write();
      var loads = 0;
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            gitWriteOperationsProvider.overrideWithValue(write),
            repoStatusProvider(repo).overrideWith((ref) {
              loads++;
              return loads == 1 ? Future.value(_status) : statusGate.future;
            }),
            unstagedFileDiffProvider((repo, _entry.path)).overrideWith(
              (ref) async => _diff,
            ),
          ],
          child: screenshotApp(
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
              body: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: palette.bg0,
                  child: Consumer(
                    builder: (context, ref, _) {
                      ref.watch(repoStatusProvider(repo));
                      return Column(
                        children: [
                          FileRow(repo: repo, entry: _entry, isStaged: false),
                          HunkRow(
                            hunk: _hunk,
                            index: 0,
                            staged: false,
                            isChecked: false,
                            onToggle: () {},
                            selectedLines: const {},
                            onToggleLine: (_) {},
                            onAction: () {},
                            onStash: () {},
                          ),
                          Expanded(child: DiffPreviewPane(repo: repo)),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(find.byTooltip('Stage file')));
      await tester.pump(const Duration(milliseconds: 180));
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('controls_hover_$name.png'),
      );
      await mouse.moveTo(const Offset(890, 540));
      Focus.of(
        tester.element(find.byIcon(Icons.check_box_outline_blank).first),
      ).requestFocus();
      await tester.pump(const Duration(milliseconds: 180));
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('controls_focus_$name.png'),
      );
      await mouse.moveTo(tester.getCenter(find.byTooltip('Discard hunk 1')));
      await tester.pump(const Duration(milliseconds: 180));
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('hunk_hover_$name.png'),
      );
      await mouse.moveTo(const Offset(890, 540));
      Focus.of(tester.element(find.byIcon(Icons.undo))).requestFocus();
      await tester.pump(const Duration(milliseconds: 180));
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('hunk_focus_$name.png'),
      );
      await tester.tap(find.byIcon(Icons.check_box_outline_blank).first);
      await pumpUntilPending(tester, find.byType(LinearProgressIndicator));
      expect(write.calls, 1);
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('file_pending_$name.png'),
      );
      statusGate.complete(_status);
      await tester.pump();
      await tester.tap(find.text('lib/app.dart').first);
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('diff_after_refresh_$name.png'),
      );
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('$name clean-tree state', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 550));
      final previousComparator = goldenFileComparator;
      final screenshots = PipelineScreenshotComparator('ux-l6-working-copy');
      goldenFileComparator = screenshots;
      addTearDown(() => goldenFileComparator = previousComparator);
      final repo = RepoLocation(RepoId.newId(), 'unused', 'test');
      final key = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            workingCopyStatusProvider(repo).overrideWith(
              (ref) async => const <WorkingFileEntry>[],
            ),
          ],
          child: screenshotApp(
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
              body: RepaintBoundary(
                key: key,
                child: ColoredBox(
                  color: palette.bg0,
                  child: WorkingCopyPanel(repo: repo),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('clean_tree_$name.png'),
      );
    });
  }
}
