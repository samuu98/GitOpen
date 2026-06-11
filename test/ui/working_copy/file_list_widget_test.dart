import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/application/settings/app_settings_notifier.dart';
import 'package:gitopen/application/settings/settings_store.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/file_list.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

/// FileList watches [appSettingsProvider]; the default chain would build
/// the real drift database, so tests always override it with this store.
final class _FakeSettingsStore implements SettingsStore {
  _FakeSettingsStore({this.seed = const {}});
  final Map<String, dynamic> seed;

  @override
  Future<Map<String, dynamic>> readAll() async => seed;

  @override
  Future<void> put(String key, dynamic value) async {}
}

Widget _host(Widget child, {Map<String, dynamic> settings = const {}}) {
  return ProviderScope(
    overrides: [
      appSettingsProvider.overrideWith(
        (ref) => AppSettingsNotifier(_FakeSettingsStore(seed: settings)),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [AppPalette.dark()]),
      home: Scaffold(
        body: SizedBox(width: 520, height: 360, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('FileList renders staged and unstaged rows with semantics', (
    tester,
  ) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
    const unstaged = WorkingFileEntry(
      path: 'lib/app.dart',
      indexState: WorkingFileState.unmodified,
      workingTreeState: WorkingFileState.modified,
    );
    const staged = WorkingFileEntry(
      path: 'README.md',
      indexState: WorkingFileState.added,
      workingTreeState: WorkingFileState.unmodified,
    );
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _host(
        Column(
          children: [
            Expanded(
              child: FileList(
                repo: repo,
                unstaged: const [unstaged],
                staged: const [staged],
              ),
            ),
            Consumer(
              builder: (_, ref, _) {
                final selected = ref.watch(selectedFileProvider);
                return Text('selected:${selected?.path ?? 'none'}');
              },
            ),
          ],
        ),
      ),
    );

    expect(find.text('Unstaged (1)'), findsOneWidget);
    expect(find.text('Staged (1)'), findsOneWidget);
    expect(find.text('lib/app.dart'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    final unstagedNode = tester.getSemantics(
      find.bySemanticsLabel('Unstaged modified file lib/app.dart'),
    );
    final stagedNode = tester.getSemantics(
      find.bySemanticsLabel('Staged added file README.md'),
    );
    expect(unstagedNode.flagsCollection.isButton, isTrue);
    expect(stagedNode.flagsCollection.isButton, isTrue);

    await tester.tap(find.text('lib/app.dart'));
    await tester.pump();

    expect(find.text('selected:lib/app.dart'), findsOneWidget);
    final selectedNode = tester.getSemantics(
      find.bySemanticsLabel('Unstaged modified file lib/app.dart'),
    );
    expect(selectedNode.flagsCollection.isButton, isTrue);
    expect(selectedNode.flagsCollection.isSelected, Tristate.isTrue);
    semantics.dispose();
  });

  testWidgets('tree mode folds paths and collapses folders', (tester) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
    const a = WorkingFileEntry(
      path: 'src/app/a.dart',
      indexState: WorkingFileState.unmodified,
      workingTreeState: WorkingFileState.modified,
    );
    const b = WorkingFileEntry(
      path: 'src/app/b.dart',
      indexState: WorkingFileState.unmodified,
      workingTreeState: WorkingFileState.modified,
    );
    await tester.pumpWidget(
      _host(
        FileList(repo: repo, unstaged: const [a, b], staged: const []),
        settings: const {'file_lists_as_tree': true},
      ),
    );
    await tester.pumpAndSettle(); // settings _load

    // Compressed chain folder + leaf names (not full paths).
    expect(find.text('src/app'), findsOneWidget);
    expect(find.text('a.dart'), findsOneWidget);
    expect(find.text('src/app/a.dart'), findsNothing);

    // Collapsing the folder hides its leaves.
    await tester.tap(find.text('src/app'));
    await tester.pump();
    expect(find.text('a.dart'), findsNothing);
    expect(find.text('b.dart'), findsNothing);
  });
}
