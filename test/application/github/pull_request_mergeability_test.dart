import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/github/github_models.dart';

PullRequestDetail _pr({
  String state = 'open',
  bool isDraft = false,
  bool? mergeable = true,
  String mergeStateStatus = 'clean',
}) {
  final t = DateTime(2026);
  return PullRequestDetail(
    number: 1,
    nodeId: 'n',
    title: 't',
    body: '',
    author: 'a',
    state: state,
    isDraft: isDraft,
    mergeable: mergeable,
    mergeStateStatus: mergeStateStatus,
    baseRef: 'main',
    headRef: 'feat',
    headSha: 'sha',
    htmlUrl: 'https://x',
    createdAt: t,
    updatedAt: t,
  );
}

void main() {
  group('PullRequestDetail.mergeBlock mirrors GitHub mergeable_state', () {
    test('clean is mergeable', () {
      expect(_pr().mergeBlock, MergeBlock.none);
      expect(_pr().canMerge, isTrue);
    });

    test('has_hooks and unstable are mergeable like GitHub', () {
      expect(_pr(mergeStateStatus: 'has_hooks').mergeBlock, MergeBlock.none);
      expect(_pr(mergeStateStatus: 'unstable').mergeBlock, MergeBlock.none);
    });

    test('blocked (branch protection / required checks) cannot merge', () {
      expect(_pr(mergeStateStatus: 'blocked').mergeBlock, MergeBlock.blocked);
      expect(_pr(mergeStateStatus: 'blocked').canMerge, isFalse);
    });

    test('dirty maps to conflicts', () {
      expect(_pr(mergeStateStatus: 'dirty').mergeBlock, MergeBlock.conflicts);
    });

    test('behind maps to behind', () {
      expect(_pr(mergeStateStatus: 'behind').mergeBlock, MergeBlock.behind);
    });

    test('unknown / empty means still computing', () {
      expect(_pr(mergeStateStatus: 'unknown').mergeBlock, MergeBlock.checking);
      expect(_pr(mergeStateStatus: '').mergeBlock, MergeBlock.checking);
    });

    test('draft cannot merge even when clean', () {
      expect(_pr(isDraft: true).mergeBlock, MergeBlock.draft);
    });

    test('a non-open PR cannot merge', () {
      expect(_pr(state: 'closed').mergeBlock, MergeBlock.notOpen);
      expect(_pr(state: 'closed').canMerge, isFalse);
    });
  });
}
