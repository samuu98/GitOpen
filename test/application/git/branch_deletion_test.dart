import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/branch_deletion.dart';
import 'package:gitopen/domain/refs/branch.dart';

Branch _local(String name, {bool current = false, String? upstream}) => Branch(
      name: name,
      fullName: 'refs/heads/$name',
      isRemote: false,
      isCurrent: current,
      ahead: 0,
      behind: 0,
      upstreamFullName: upstream,
    );

Branch _remote(String shortWithRemote) => Branch(
      name: shortWithRemote, // e.g. "origin/feature"
      fullName: 'refs/remotes/$shortWithRemote',
      isRemote: true,
      isCurrent: false,
      ahead: 0,
      behind: 0,
    );

void main() {
  group('branchDeletionTargets', () {
    test('local with upstream maps to both sides', () {
      final t = branchDeletionTargets(
        _local('feature', upstream: 'refs/remotes/origin/feature'),
        [_local('feature', upstream: 'refs/remotes/origin/feature')],
      );
      expect(t.localName, 'feature');
      expect(t.localIsCurrent, isFalse);
      expect(t.remoteRef, 'origin/feature');
    });

    test('local without upstream has no remote side', () {
      final t = branchDeletionTargets(_local('feature'), [_local('feature')]);
      expect(t.localName, 'feature');
      expect(t.remoteRef, isNull);
    });

    test('current local is flagged', () {
      final t = branchDeletionTargets(
        _local('main', current: true),
        [_local('main', current: true)],
      );
      expect(t.localIsCurrent, isTrue);
    });

    test('remote maps to the local that tracks it', () {
      final all = [
        _local('feature', upstream: 'refs/remotes/origin/feature'),
        _remote('origin/feature'),
      ];
      final t = branchDeletionTargets(_remote('origin/feature'), all);
      expect(t.remoteRef, 'origin/feature');
      expect(t.localName, 'feature');
    });

    test('remote with no tracking local has no local side', () {
      final t = branchDeletionTargets(
        _remote('origin/feature'),
        [_remote('origin/feature')],
      );
      expect(t.remoteRef, 'origin/feature');
      expect(t.localName, isNull);
    });

    test('upstream not under refs/remotes is ignored (defensive)', () {
      final t = branchDeletionTargets(
        _local('feature', upstream: 'refs/heads/weird'),
        [_local('feature', upstream: 'refs/heads/weird')],
      );
      expect(t.remoteRef, isNull);
    });
  });

  group('isNotFullyMergedError', () {
    test('matches git not-fully-merged message', () {
      expect(
        isNotFullyMergedError("error: the branch 'x' is not fully merged."),
        isTrue,
      );
    });
    test('false for other errors', () {
      expect(isNotFullyMergedError('error: branch not found'), isFalse);
    });
  });
}
