import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/files/file_content.dart';
import 'package:gitopen/domain/files/file_revision.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/image_diff_view.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Engine-encoded 1×1 PNG, generated at runtime so the bytes are guaranteed
/// decodable by the same codec the widget uses.
Future<Uint8List> _makePng(WidgetTester tester) async {
  final png = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      const ui.Rect.fromLTWH(0, 0, 1, 1),
      ui.Paint()..color = const ui.Color(0xFFFF0000),
    );
    final image = await recorder.endRecording().toImage(1, 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return png!;
}

final class _FakeReadOps implements GitReadOperations {
  _FakeReadOps(this.png);
  final Uint8List png;

  @override
  Future<FileContent> getFileBytes(
    RepoLocation repo,
    FileRevision revision,
    String path, {
    int maxBytes = kFilePreviewMaxBytes,
  }) async {
    return switch (revision) {
      FileRevisionParentOfCommit() => FileContent.missing,
      FileRevisionAtCommit() =>
        FileContent(exists: true, sizeBytes: png.length, bytes: png),
      _ => const FileContent(exists: true, sizeBytes: 30 * 1024 * 1024),
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  final png = await _makePng(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gitReadOperationsProvider.overrideWithValue(_FakeReadOps(png)),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [AppPalette.dark()]),
        home: Scaffold(body: SizedBox(width: 700, height: 400, child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');
  final sha = CommitSha('a' * 40);

  testWidgets('renders a missing old side and an image new side',
      (tester) async {
    await _pump(
      tester,
      ImageDiffView(
        repo: repo,
        oldPath: 'img.png',
        newPath: 'img.png',
        oldRevision: FileRevisionParentOfCommit(sha),
        newRevision: FileRevisionAtCommit(sha),
      ),
    );
    expect(find.text('Old'), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Not present'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    // Byte-size label of the new side.
    expect(find.textContaining(' B'), findsOneWidget);
  });

  testWidgets('renders an explicit too-large state', (tester) async {
    await _pump(
      tester,
      ImageDiffView(
        repo: repo,
        oldPath: 'img.png',
        newPath: 'img.png',
        oldRevision: const FileRevisionIndex(),
        newRevision: const FileRevisionWorkingTree(),
      ),
    );
    expect(find.textContaining('Too large to preview'), findsNWidgets(2));
    expect(find.byType(Image), findsNothing);
  });
}
