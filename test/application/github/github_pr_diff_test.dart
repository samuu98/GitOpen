import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/github/github_pr_diff.dart';

void main() {
  test('parseGitHubPatch maps added and context lines', () {
    const patch = '@@ -1,2 +1,3 @@\n old\n+new\n same';

    final lines = parseGitHubPatch(patch);

    expect(lines, hasLength(3));
    expect(lines[0].oldLine, 1);
    expect(lines[0].newLine, 1);
    expect(lines[0].side, 'RIGHT');
    expect(lines[1].oldLine, isNull);
    expect(lines[1].newLine, 2);
    expect(lines[1].side, 'RIGHT');
    expect(lines[1].isCommentable, isTrue);
  });

  test('parseGitHubPatch maps deleted lines to LEFT side', () {
    const patch = '@@ -4,2 +4,1 @@\n keep\n-delete me';

    final deleted = parseGitHubPatch(patch).last;

    expect(deleted.oldLine, 5);
    expect(deleted.newLine, isNull);
    expect(deleted.side, 'LEFT');
    expect(deleted.commentLine, 5);
  });

  test('parseGitHubPatch supports multiple hunks', () {
    const patch = '@@ -1 +1 @@\n-a\n+b\n@@ -10 +10 @@\n c';

    final lines = parseGitHubPatch(patch);

    expect(lines.map((l) => l.content), ['-a', '+b', ' c']);
    expect(lines.last.oldLine, 10);
    expect(lines.last.newLine, 10);
  });
}
