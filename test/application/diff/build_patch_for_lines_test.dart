import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/diff/build_patch_for_lines.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';

void main() {
  const hunk = DiffHunk(
    oldStart: 1,
    oldCount: 2,
    newStart: 1,
    newCount: 3,
    header: '@@ -1,2 +1,3 @@',
    lines: [
      DiffLine(
        kind: DiffLineKind.context,
        content: 'a',
        oldLine: 1,
        newLine: 1,
      ),
      DiffLine(kind: DiffLineKind.deletion, content: 'b', oldLine: 2),
      DiffLine(kind: DiffLineKind.addition, content: 'X', newLine: 2),
      DiffLine(kind: DiffLineKind.addition, content: 'c', newLine: 3),
    ],
  );

  test('selecting all lines reproduces the whole hunk', () {
    final patch = buildPatchForLines('f.txt', hunk, {1, 2, 3});

    expect(patch, contains('@@ -1,2 +1,3 @@'));
    expect(patch, contains('-b'));
    expect(patch, contains('+X'));
    expect(patch, contains('+c'));
  });

  test('unselected addition is dropped and counts recomputed', () {
    final patch = buildPatchForLines('f.txt', hunk, {1, 2});

    expect(patch, contains('@@ -1,2 +1,2 @@'));
    expect(patch, contains('-b'));
    expect(patch, contains('+X'));
    expect(patch, isNot(contains('+c')));
  });

  test('unselected deletion becomes context', () {
    final patch = buildPatchForLines('f.txt', hunk, {2, 3});

    expect(patch, contains('@@ -1,2 +1,4 @@'));
    expect(patch, contains(' b'));
    expect(patch, isNot(contains('-b')));
  });

  test('no selected changes yields empty string', () {
    expect(buildPatchForLines('f.txt', hunk, <int>{}), isEmpty);
  });
}
