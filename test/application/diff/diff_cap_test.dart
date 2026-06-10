import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/diff/diff_cap.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/domain/diff/diff_result.dart';
import 'package:gitopen/domain/diff/file_diff.dart';

DiffHunk _hunk(int lines) => DiffHunk(
      oldStart: 1,
      oldCount: lines,
      newStart: 1,
      newCount: lines,
      header: '@@',
      lines: List.generate(
        lines,
        (i) => DiffLine(
          kind: DiffLineKind.context,
          content: 'l$i',
          oldLine: i + 1,
          newLine: i + 1,
        ),
      ),
    );

FileDiff _file(List<DiffHunk> hunks) => FileDiff(
      path: 'a.txt',
      changeKind: FileChangeKind.modified,
      isBinary: false,
      linesAdded: 0,
      linesDeleted: 0,
      hunks: hunks,
    );

void main() {
  test('small files pass through untouched (identical instance)', () {
    final f = _file([_hunk(10)]);
    final out = capDiffResult(DiffResult(files: [f]), maxLines: 100);
    expect(identical(out.files.single, f), isTrue);
    expect(out.files.single.truncated, isFalse);
  });

  test('keeps whole hunks up to the cap and marks truncated', () {
    final out = capDiffResult(
      DiffResult(files: [
        _file([_hunk(60), _hunk(60)]),
      ]),
      maxLines: 100,
    );
    expect(out.files.single.hunks, hasLength(1));
    expect(out.files.single.truncated, isTrue);
  });

  test('a single over-cap hunk yields zero hunks, truncated', () {
    final out = capDiffResult(
      DiffResult(files: [
        _file([_hunk(150)]),
      ]),
      maxLines: 100,
    );
    expect(out.files.single.hunks, isEmpty);
    expect(out.files.single.truncated, isTrue);
  });
}
