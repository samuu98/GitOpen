import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/ui/common/app_empty_state.dart';
import 'package:gitopen/ui/common/app_panel_state.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:gitopen/ui/working_copy/diff_preview_pane.dart';
import 'package:gitopen/ui/working_copy/working_copy_panel.dart';
import 'package:gitopen/ui/working_copy/working_copy_providers.dart';

void main() {
  testWidgets('working copy shows shared loading and clean states', (
    tester,
  ) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'test');
    final pending = Completer<List<WorkingFileEntry>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workingCopyStatusProvider(repo).overrideWith(
            (ref) => pending.future,
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(body: WorkingCopyPanel(repo: repo)),
        ),
      ),
    );
    expect(find.byType(AppLoadingState), findsOneWidget);
    pending.complete([]);
    await tester.pump();
    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('Working tree clean'), findsOneWidget);
  });

  testWidgets('working copy error uses shared retry state', (tester) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'test');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workingCopyStatusProvider(repo).overrideWith(
            (ref) =>
                Future<List<WorkingFileEntry>>.error(StateError('bad status')),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(body: WorkingCopyPanel(repo: repo)),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('diff without a selection uses shared empty state', (
    tester,
  ) async {
    final repo = RepoLocation(RepoId.newId(), 'unused', 'test');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(body: DiffPreviewPane(repo: repo)),
        ),
      ),
    );
    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('Select a file to preview changes'), findsOneWidget);
  });
}
