import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/diff/build_patch_for_hunks.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';

void main() {
  group('buildPatchForHunks', () {
    const hunk = DiffHunk(
      oldStart: 1,
      oldCount: 2,
      newStart: 1,
      newCount: 2,
      header: '@@ -1,2 +1,2 @@',
      lines: [
        DiffLine(kind: DiffLineKind.context, content: 'unchanged'),
        DiffLine(kind: DiffLineKind.deletion, content: 'old line'),
        DiffLine(kind: DiffLineKind.addition, content: 'new line'),
      ],
    );

    test('prefixes context, deletion, and addition lines', () {
      final patch = buildPatchForHunks('lib/a.dart', [hunk]);
      expect(
        patch,
        'diff --git a/lib/a.dart b/lib/a.dart\n'
        '--- a/lib/a.dart\n'
        '+++ b/lib/a.dart\n'
        '@@ -1,2 +1,2 @@\n'
        ' unchanged\n'
        '-old line\n'
        '+new line\n',
      );
    });

    test('includes only the supplied hunks, in order', () {
      const second = DiffHunk(
        oldStart: 10,
        oldCount: 1,
        newStart: 10,
        newCount: 2,
        header: '@@ -10,1 +10,2 @@',
        lines: [
          DiffLine(kind: DiffLineKind.addition, content: 'tail'),
        ],
      );
      final patch = buildPatchForHunks('x.txt', [hunk, second]);
      expect(
        patch.indexOf('@@ -1,2 +1,2 @@'),
        lessThan(patch.indexOf('@@ -10,1 +10,2 @@')),
      );
      expect(patch, endsWith('@@ -10,1 +10,2 @@\n+tail\n'));
    });

    test('produces a header-only patch for an empty hunk list', () {
      expect(
        buildPatchForHunks('x.txt', []),
        'diff --git a/x.txt b/x.txt\n'
        '--- a/x.txt\n'
        '+++ b/x.txt\n',
      );
    });
  });
}
