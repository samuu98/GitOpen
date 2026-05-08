import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/commit_graph/commit_graph_layout.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/commits/commit_signature.dart';

CommitInfo mk(String sha, [List<String> parents = const []]) {
  final pad = sha.padLeft(8, '0');
  final sig = CommitSignature('a', 'a@x', DateTime.utc(2024));
  return CommitInfo(
    sha: CommitSha(pad),
    parentShas: parents.map((p) => CommitSha(p.padLeft(8, '0'))).toList(),
    author: sig,
    committer: sig,
    summary: 'msg',
    message: 'msg',
  );
}

void main() {
  group('CommitGraphLayout', () {
    test('linear history all in lane 0', () {
      final commits = [mk('c', ['b']), mk('b', ['a']), mk('a')];
      final nodes = const DefaultCommitGraphLayout().compute(commits);
      expect(nodes, hasLength(3));
      expect(nodes.every((n) => n.lane == 0), isTrue);
    });

    test('branch creates two lanes; root collapses back', () {
      final commits = [
        mk('c',  ['b1', 'b2']),
        mk('b1', ['a']),
        mk('b2', ['a']),
        mk('a'),
      ];
      final nodes = const DefaultCommitGraphLayout().compute(commits);
      final lanes = nodes.map((n) => n.lane).toSet();
      expect(lanes, containsAll([0, 1]));
      expect(nodes.last.lane, 0);
    });

    test('empty input returns empty', () {
      expect(const DefaultCommitGraphLayout().compute(const []), isEmpty);
    });
  });
}
