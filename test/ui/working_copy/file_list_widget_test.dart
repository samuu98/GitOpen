import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/file_list.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

Widget _host(Widget child) {
  return ProviderScope(
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
}
