import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/domain/diff/diff_result.dart';
import 'package:gitopen/domain/diff/diff_spec.dart';
import 'package:gitopen/domain/diff/file_diff.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// A [GitReadOperations] that returns a canned [DiffResult] for `getDiff`.
/// Everything else throws (via [noSuchMethod]) so tests fail loudly if the
/// widget under test calls an unstubbed read.
final class FakeDiffReadOps implements GitReadOperations {
  FakeDiffReadOps(this.result);
  final DiffResult result;

  @override
  Future<DiffResult> getDiff(
    RepoLocation repo,
    DiffSpec spec, {
    bool ignoreWhitespace = false,
  }) async => result;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Builds a one-hunk [FileDiff] with the given content lines (all additions by
/// default), for diff-view widget tests.
FileDiff fileDiffFixture(
  String path, {
  FileChangeKind kind = FileChangeKind.modified,
  int linesAdded = 1,
  int linesDeleted = 0,
  String? oldPath,
  List<DiffLine>? lines,
  String header = '@@ -1,1 +1,2 @@',
}) {
  final hunkLines = lines ??
      const [
        DiffLine(
          kind: DiffLineKind.addition,
          content: 'const x = 1;',
          newLine: 1,
        ),
      ];
  return FileDiff(
    path: path,
    oldPath: oldPath,
    changeKind: kind,
    isBinary: false,
    linesAdded: linesAdded,
    linesDeleted: linesDeleted,
    hunks: [
      DiffHunk(
        oldStart: 1,
        oldCount: 1,
        newStart: 1,
        newCount: 2,
        header: header,
        lines: hunkLines,
      ),
    ],
  );
}

DiffResult diffOf(List<FileDiff> files) => DiffResult(files: files);

RepoLocation testRepo() => RepoLocation(RepoId.newId(), 'unused', 'repo');

/// Wraps [child] in a ProviderScope + MaterialApp with the dark palette and a
/// fixed-size viewport, applying [overrides].
Widget wrapWithApp(
  Widget child, {
  List<Override> overrides = const [],
  Size size = const Size(900, 600),
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: ThemeData(extensions: [AppPalette.dark()]),
      home: Scaffold(
        body: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );
}
