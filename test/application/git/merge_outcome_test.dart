import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';

void main() {
  group('MergeStrategy', () {
    test('has the four documented variants in order', () {
      expect(MergeStrategy.values, [
        MergeStrategy.defaultStrategy,
        MergeStrategy.noFF,
        MergeStrategy.squash,
        MergeStrategy.noCommit,
      ]);
    });
  });

  group('MergePreview', () {
    test('MergePreviewClean constructs', () {
      const preview = MergePreviewClean();
      expect(preview, isA<MergePreview>());
    });

    test('MergePreviewConflicts carries conflicted paths', () {
      const preview = MergePreviewConflicts(['a.txt', 'b.txt']);
      expect(preview.conflictedPaths, ['a.txt', 'b.txt']);
      expect(preview, isA<MergePreview>());
    });

    test('exhaustive switch resolves each variant', () {
      String label(MergePreview preview) => switch (preview) {
            MergePreviewClean() => 'clean',
            MergePreviewConflicts(conflictedPaths: final p) =>
              'conflicts:${p.length}',
          };
      expect(label(const MergePreviewClean()), 'clean');
      expect(label(const MergePreviewConflicts(['x'])), 'conflicts:1');
    });
  });

  group('MergeOutcome', () {
    test('MergeFastForward carries the new head', () {
      final outcome = MergeFastForward(CommitSha('abcd1234'));
      expect(outcome.newHead.value, 'abcd1234');
      expect(outcome, isA<MergeOutcome>());
    });

    test('MergeMerged carries the merge commit', () {
      final outcome = MergeMerged(CommitSha('deadbeef'));
      expect(outcome.mergeCommit.value, 'deadbeef');
      expect(outcome, isA<MergeOutcome>());
    });

    test('MergeStaged constructs', () {
      const outcome = MergeStaged();
      expect(outcome, isA<MergeOutcome>());
    });

    test('MergeUpToDate constructs', () {
      const outcome = MergeUpToDate();
      expect(outcome, isA<MergeOutcome>());
    });

    test('MergeConflict carries conflicted paths', () {
      const outcome = MergeConflict(['conflict.dart']);
      expect(outcome.conflictedPaths, ['conflict.dart']);
      expect(outcome, isA<MergeOutcome>());
    });

    test('exhaustive switch resolves each variant', () {
      final outcomes = <MergeOutcome>[
        MergeFastForward(CommitSha('aaaa1111')),
        MergeMerged(CommitSha('bbbb2222')),
        const MergeStaged(),
        const MergeUpToDate(),
        const MergeConflict(['c.dart']),
      ];
      final labels = outcomes
          .map(
            (o) => switch (o) {
              MergeFastForward() => 'ff',
              MergeMerged() => 'merged',
              MergeStaged() => 'staged',
              MergeUpToDate() => 'uptodate',
              MergeConflict() => 'conflict',
            },
          )
          .toList();
      expect(labels, ['ff', 'merged', 'staged', 'uptodate', 'conflict']);
    });
  });

  group('CherryPickOutcome', () {
    test('CherryPickApplied carries the new commit', () {
      final outcome = CherryPickApplied(CommitSha('cafe1234'));
      expect(outcome.newCommit.value, 'cafe1234');
      expect(outcome, isA<CherryPickOutcome>());
    });

    test('CherryPickConflict carries conflicted paths', () {
      const outcome = CherryPickConflict(['picked.dart']);
      expect(outcome.conflictedPaths, ['picked.dart']);
      expect(outcome, isA<CherryPickOutcome>());
    });

    test('exhaustive switch resolves each variant', () {
      final outcomes = <CherryPickOutcome>[
        CherryPickApplied(CommitSha('1234abcd')),
        const CherryPickConflict(['x']),
      ];
      final labels = outcomes
          .map(
            (o) => switch (o) {
              CherryPickApplied() => 'applied',
              CherryPickConflict() => 'conflict',
            },
          )
          .toList();
      expect(labels, ['applied', 'conflict']);
    });
  });

  group('RevertOutcome', () {
    test('RevertApplied carries the new commit', () {
      final outcome = RevertApplied(CommitSha('feed0000'));
      expect(outcome.newCommit.value, 'feed0000');
      expect(outcome, isA<RevertOutcome>());
    });

    test('RevertConflict carries conflicted paths', () {
      const outcome = RevertConflict(['reverted.dart']);
      expect(outcome.conflictedPaths, ['reverted.dart']);
      expect(outcome, isA<RevertOutcome>());
    });

    test('exhaustive switch resolves each variant', () {
      final outcomes = <RevertOutcome>[
        RevertApplied(CommitSha('99aa88bb')),
        const RevertConflict(['x', 'y']),
      ];
      final labels = outcomes
          .map(
            (o) => switch (o) {
              RevertApplied() => 'applied',
              RevertConflict(conflictedPaths: final p) =>
                'conflict:${p.length}',
            },
          )
          .toList();
      expect(labels, ['applied', 'conflict:2']);
    });
  });

  group('RebaseOutcome', () {
    test('RebaseApplied carries the new head', () {
      final outcome = RebaseApplied(CommitSha('0badf00d'));
      expect(outcome.newHead.value, '0badf00d');
      expect(outcome, isA<RebaseOutcome>());
    });

    test('RebaseUpToDate constructs', () {
      const outcome = RebaseUpToDate();
      expect(outcome, isA<RebaseOutcome>());
    });

    test('RebaseConflict carries conflicted paths', () {
      const outcome = RebaseConflict(['rebased.dart']);
      expect(outcome.conflictedPaths, ['rebased.dart']);
      expect(outcome, isA<RebaseOutcome>());
    });

    test('exhaustive switch resolves each variant', () {
      final outcomes = <RebaseOutcome>[
        RebaseApplied(CommitSha('11223344')),
        const RebaseUpToDate(),
        const RebaseConflict(['x']),
        const RebaseStoppedForEdit(),
      ];
      final labels = outcomes
          .map(
            (o) => switch (o) {
              RebaseApplied() => 'applied',
              RebaseUpToDate() => 'uptodate',
              RebaseConflict() => 'conflict',
              RebaseStoppedForEdit() => 'stopped',
            },
          )
          .toList();
      expect(labels, ['applied', 'uptodate', 'conflict', 'stopped']);
    });
  });
}
