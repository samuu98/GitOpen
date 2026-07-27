import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/diff/diff_render_budget.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/domain/diff/file_diff.dart';

FileDiff _file(String path, int lines, {bool binary = false}) => FileDiff(
      path: path,
      changeKind: FileChangeKind.modified,
      isBinary: binary,
      linesAdded: lines,
      linesDeleted: 0,
      hunks: binary
          ? const []
          : [
              DiffHunk(
                oldStart: 1,
                oldCount: 1,
                newStart: 1,
                newCount: lines,
                header: '@@ -1,1 +1,$lines @@',
                lines: [
                  for (var i = 0; i < lines; i++)
                    DiffLine(
                      kind: DiffLineKind.addition,
                      content: 'line $i',
                      newLine: i + 1,
                    ),
                ],
              ),
            ],
    );

void main() {
  group('initiallyExpandedPaths', () {
    test('expands everything in a small diff', () {
      final files = [_file('a.dart', 10), _file('b.dart', 20)];
      expect(
        initiallyExpandedPaths(files),
        {'a.dart', 'b.dart'},
      );
    });

    test('stops once the line budget is spent', () {
      final files = [
        _file('a.dart', 60),
        _file('b.dart', 30),
        _file('c.dart', 30), // would cross the budget
        _file('d.dart', 1),
      ];
      // Files are taken in order, whole: a+b = 90 fits, c would reach 120.
      expect(
        initiallyExpandedPaths(files, lineBudget: 100),
        {'a.dart', 'b.dart'},
      );
    });

    test('caps the number of expanded files even when they are tiny', () {
      final files = [for (var i = 0; i < 50; i++) _file('f$i.dart', 1)];
      expect(
        initiallyExpandedPaths(files, lineBudget: 10000, fileCap: 8),
        hasLength(8),
      );
    });

    test('always expands the first file, however big it is', () {
      final files = [_file('huge.dart', 5000), _file('small.dart', 1)];
      final expanded = initiallyExpandedPaths(files, lineBudget: 100);
      expect(expanded, {'huge.dart'});
    });

    test('binary files cost a flat amount instead of zero', () {
      // Binary files have no hunk lines but still render an image decode or a
      // placeholder, so they must consume budget — otherwise a commit of 400
      // screenshots expands all of them.
      final files = [for (var i = 0; i < 400; i++) _file('img$i.png', 0,
          binary: true,)];
      final expanded = initiallyExpandedPaths(files);
      expect(expanded.length, lessThan(files.length));
    });

    test('an empty diff expands nothing', () {
      expect(initiallyExpandedPaths(const []), isEmpty);
    });
  });
}
