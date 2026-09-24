import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/branch_visibility_provider.dart';
import 'package:gitopen/application/git/branch_deletion_flow.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings_notifier.dart';
import 'package:gitopen/application/settings/settings_store.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/app_interactive_surface.dart';
import 'package:gitopen/ui/sidebar/branch_tree.dart';
import 'package:gitopen/ui/sidebar/branch_tree_view.dart';
import 'package:gitopen/ui/sidebar/sidebar_shared.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

const _local = Branch(
  name: 'develop',
  fullName: 'refs/heads/develop',
  isRemote: false,
  isCurrent: false,
  ahead: 0,
  behind: 0,
);

const _current = Branch(
  name: 'master',
  fullName: 'refs/heads/master',
  isRemote: false,
  isCurrent: true,
  ahead: 0,
  behind: 0,
);

const _remote = Branch(
  name: 'origin/feature',
  fullName: 'refs/remotes/origin/feature',
  isRemote: true,
  isCurrent: false,
  ahead: 0,
  behind: 0,
);

const _repo = RepoLocation(RepoId('t'), 'unused', 't');

final class _FakeSettingsStore implements SettingsStore {
  @override
  Future<Map<String, dynamic>> readAll() async => const {};

  @override
  Future<void> put(String key, dynamic value) async {}
}

class _Inspector implements BranchDeletionInspector {
  @override
  Future<BranchDeleteStatus> inspect(RepoLocation repo, String name) async =>
      const BranchDeleteStatus(exists: true, merged: true);

  @override
  Future<WorktreeDeleteStatus?> inspectWorktree(
    RepoLocation repo,
    String path,
  ) async => null;
}

class _Write implements GitWriteOperations {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Widget _host(List<Branch> branches) => ProviderScope(
  overrides: [
    branchesProvider(_repo).overrideWith((ref) async => branches),
    branchDeletionFlowProvider.overrideWithValue(
      BranchDeletionFlow(inspector: _Inspector(), write: _Write()),
    ),
    // The ahead/behind badge watches this; stub it so the widget test does
    // not spawn a real `git for-each-ref` (which hangs FakeAsync).
    branchDivergenceProvider(_repo).overrideWith(
      (ref) async => const <String, ({int ahead, int behind})>{},
    ),
    appSettingsProvider.overrideWith(
      (ref) => AppSettingsNotifier(_FakeSettingsStore()),
    ),
  ],
  child: MaterialApp(
    theme: ThemeData(extensions: [AppPalette.dark()]),
    home: Scaffold(
      body: SingleChildScrollView(
        child: BranchTreeView(
          nodes: BranchTree.build(branches),
          repo: _repo,
        ),
      ),
    ),
  ),
);

/// The Ahem test font renders every glyph as a full-width square, so the
/// fixed-width context-menu rows overflow by a few pixels in tests only.
/// Swallow exactly that error; everything else still fails the test.
void ignoreMenuOverflow() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed by')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

const _folderChild = Branch(
  name: 'feat/widget',
  fullName: 'refs/heads/feat/widget',
  isRemote: false,
  isCurrent: false,
  ahead: 0,
  behind: 0,
);

double _rowLeft(WidgetTester tester, String label) {
  final padding = tester.widget<Padding>(
    find.ancestor(of: find.text(label), matching: find.byType(Padding)).first,
  );
  return (padding.padding as EdgeInsets).left;
}

void main() {
  bool selected(WidgetTester tester, String label) => tester
      .widget<AppInteractiveSurface>(
        find
            .ancestor(
              of: find.text(label),
              matching: find.byType(AppInteractiveSurface),
            )
            .first,
      )
      .selected;

  testWidgets('Ctrl toggle, Shift range, click and Esc clear', (tester) async {
    const third = Branch(
      name: 'third',
      fullName: 'refs/heads/third',
      isRemote: false,
      isCurrent: false,
      ahead: 0,
      behind: 0,
    );
    await tester.pumpWidget(_host([_local, _current, third]));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    expect(HardwareKeyboard.instance.isControlPressed, isTrue);
    await tester.tap(find.text('develop'));
    await tester.pumpAndSettle();
    expect(selected(tester, 'develop'), isTrue);
    await tester.tap(find.text('third'));
    await tester.pumpAndSettle();
    expect(selected(tester, 'third'), isTrue);
    await tester.tap(find.text('develop'));
    await tester.pumpAndSettle();
    expect(selected(tester, 'develop'), isFalse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(find.text('third'));
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(selected(tester, 'develop'), isTrue);
    expect(selected(tester, 'master'), isTrue);
    expect(selected(tester, 'third'), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(selected(tester, 'develop'), isFalse);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('develop'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.tap(find.text('master'));
    await tester.pumpAndSettle();
    expect(selected(tester, 'develop'), isFalse);
  });

  testWidgets('folder context menu offers delete all descendants', (
    tester,
  ) async {
    ignoreMenuOverflow();
    await tester.pumpWidget(_host([_folderChild]));
    await tester.tap(find.text('feat'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Delete all branches in feat/…'), findsOneWidget);
    await tester.tap(find.text('Delete all branches in feat/…'));
    await tester.pumpAndSettle();
    expect(find.text('Delete branch?'), findsOneWidget);
    expect(find.text('feat/widget'), findsOneWidget);
  });

  testWidgets('Delete key opens one dialog for selected remote branches', (
    tester,
  ) async {
    const second = Branch(
      name: 'origin/other',
      fullName: 'refs/remotes/origin/other',
      isRemote: true,
      isCurrent: false,
      ahead: 0,
      behind: 0,
    );
    await tester.pumpWidget(_host([_remote, second]));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('feature'));
    await tester.tap(find.text('other'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 branches?'), findsOneWidget);
    expect(find.text('origin/feature'), findsOneWidget);
    expect(find.text('origin/other'), findsOneWidget);
  });
  testWidgets(
    'folderless branches align with folders; nested branches indent one step',
    (tester) async {
      await tester.pumpWidget(_host([_folderChild, _local]));
      await tester.pump();

      final folder = _rowLeft(tester, 'feat'); // folder, depth 0
      final folderless = _rowLeft(tester, 'develop'); // leaf, depth 0
      final nested = _rowLeft(tester, 'widget'); // leaf inside 'feat', depth 1

      // The reported bug: a folderless branch sat one step deeper than a
      // sibling folder. They must share the same column.
      expect(folderless, folder);
      // A branch inside a folder sits exactly one nesting step deeper.
      expect(nested, folder + kSidebarIndentStep);
    },
  );

  testWidgets('renders branches; current branch carries the ✓ marker', (
    tester,
  ) async {
    await tester.pumpWidget(_host([_current, _local]));
    expect(find.text('master'), findsOneWidget);
    expect(find.text('develop'), findsOneWidget);
    expect(find.text('✓'), findsOneWidget);
  });

  testWidgets('local branch context menu offers Checkout and Rename', (
    tester,
  ) async {
    ignoreMenuOverflow();
    await tester.pumpWidget(_host([_current, _local]));
    await tester.tap(find.text('develop'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Checkout'), findsOneWidget);
    expect(find.text('Rename…'), findsOneWidget);
  });

  testWidgets(
    'remote branch context menu offers Checkout as local branch, no Rename',
    (tester) async {
      ignoreMenuOverflow();
      await tester.pumpWidget(_host([_current, _remote]));
      // The remote branch renders nested under an 'origin' folder.
      expect(find.text('origin'), findsOneWidget);
      await tester.tap(find.text('feature'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Checkout as local branch'), findsOneWidget);
      expect(find.text('Rename…'), findsNothing);
    },
  );

  testWidgets('visibility eye toggles the ref in hiddenRefsProvider', (
    tester,
  ) async {
    await tester.pumpWidget(_host([_local]));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(BranchTreeView).first),
    );
    expect(container.read(hiddenRefsProvider), isEmpty);
    // Single branch → single visibility eye. The row's double-tap handler
    // keeps the gesture arena open for the double-tap window, so pump past
    // it before asserting.
    await tester.tap(find.byIcon(Icons.visibility));
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      container.read(hiddenRefsProvider),
      contains('refs/heads/develop'),
    );
    // Hidden rows render the off icon; tapping again unhides.
    await tester.tap(find.byIcon(Icons.visibility_off));
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(hiddenRefsProvider), isEmpty);
  });
}
