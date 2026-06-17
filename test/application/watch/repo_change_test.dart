import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/watch/repo_change.dart';
import 'package:path/path.dart' as p;

String g(List<String> parts) => p.joinAll(['/repo', '.git', ...parts]);

void main() {
  group('classifyGitChange', () {
    test('HEAD and reflog -> head', () {
      expect(classifyGitChange(g(['HEAD'])), RepoChange.head);
      expect(classifyGitChange(g(['logs', 'HEAD'])), RepoChange.head);
    });
    test('refs and packed-refs -> refs', () {
      expect(classifyGitChange(g(['refs', 'heads', 'main'])), RepoChange.refs);
      expect(classifyGitChange(g(['packed-refs'])), RepoChange.refs);
    });
    test('FETCH_HEAD / ORIG_HEAD -> fetch', () {
      expect(classifyGitChange(g(['FETCH_HEAD'])), RepoChange.fetch);
      expect(classifyGitChange(g(['ORIG_HEAD'])), RepoChange.fetch);
    });
    test('merge/rebase state -> mergeState', () {
      expect(classifyGitChange(g(['MERGE_HEAD'])), RepoChange.mergeState);
      expect(
        classifyGitChange(g(['CHERRY_PICK_HEAD'])),
        RepoChange.mergeState,
      );
      expect(classifyGitChange(g(['REVERT_HEAD'])), RepoChange.mergeState);
      expect(
        classifyGitChange(g(['rebase-merge', 'done'])),
        RepoChange.mergeState,
      );
      expect(
        classifyGitChange(g(['rebase-apply', 'next'])),
        RepoChange.mergeState,
      );
    });
    test('index and lock files -> null (noise)', () {
      expect(classifyGitChange(g(['index'])), isNull);
      expect(classifyGitChange(g(['index.lock'])), isNull);
      expect(classifyGitChange(g(['HEAD.lock'])), isNull);
      expect(classifyGitChange(g(['packed-refs.lock'])), isNull);
    });
    test('unrelated files -> null', () {
      expect(classifyGitChange(g(['config'])), isNull);
      expect(classifyGitChange(g(['description'])), isNull);
    });
  });

  group('scopesForChange', () {
    test('head refreshes worktree + refs + state', () {
      expect(scopesForChange({RepoChange.head}), {
        RepoRefreshScope.worktree,
        RepoRefreshScope.refs,
        RepoRefreshScope.state,
      });
    });
    test('refs / fetch refresh refs + state (no worktree)', () {
      expect(
        scopesForChange({RepoChange.refs}),
        {RepoRefreshScope.refs, RepoRefreshScope.state},
      );
      expect(
        scopesForChange({RepoChange.fetch}),
        {RepoRefreshScope.refs, RepoRefreshScope.state},
      );
    });
    test('mergeState refreshes worktree + state (no refs/graph)', () {
      expect(
        scopesForChange({RepoChange.mergeState}),
        {RepoRefreshScope.worktree, RepoRefreshScope.state},
      );
    });
    test('a mixed burst unions the scopes', () {
      expect(scopesForChange({RepoChange.mergeState, RepoChange.head}), {
        RepoRefreshScope.worktree,
        RepoRefreshScope.refs,
        RepoRefreshScope.state,
      });
    });
  });

  group('scopesForFocus', () {
    test('no head move -> worktree + state only', () {
      expect(
        scopesForFocus(headMoved: false),
        {RepoRefreshScope.worktree, RepoRefreshScope.state},
      );
    });
    test('head moved -> adds refs', () {
      expect(scopesForFocus(headMoved: true), {
        RepoRefreshScope.worktree,
        RepoRefreshScope.refs,
        RepoRefreshScope.state,
      });
    });
  });
}
