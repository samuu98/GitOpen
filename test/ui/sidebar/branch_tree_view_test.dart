import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/branch_visibility_provider.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
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

Widget _host(List<Branch> branches) => ProviderScope(
  overrides: [
    // The ahead/behind badge watches this; stub it so the widget test does
    // not spawn a real `git for-each-ref` (which hangs FakeAsync).
    branchDivergenceProvider(_repo).overrideWith(
      (ref) async => const <String, ({int ahead, int behind})>{},
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
