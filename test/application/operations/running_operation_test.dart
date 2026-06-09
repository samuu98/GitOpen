import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

void main() {
  final startedAt = DateTime.utc(2024, 1, 1, 12);

  RunningOperation base() => RunningOperation(
        id: 'op-1',
        kind: OpKind.push,
        label: 'Pushing origin',
        startedAt: startedAt,
      );

  group('OpKind / OperationStatus enums', () {
    test('OpKind covers all documented kinds', () {
      expect(OpKind.values, [
        OpKind.fetch,
        OpKind.pull,
        OpKind.push,
        OpKind.clone,
        OpKind.commit,
        OpKind.merge,
        OpKind.cherryPick,
        OpKind.stash,
        OpKind.branch,
        OpKind.reset,
        OpKind.other,
      ]);
    });

    test('OperationStatus covers the lifecycle states', () {
      expect(OperationStatus.values, [
        OperationStatus.pending,
        OperationStatus.running,
        OperationStatus.success,
        OperationStatus.failed,
        OperationStatus.cancelled,
      ]);
    });
  });

  group('RunningOperation construction', () {
    test('applies documented defaults', () {
      final op = base();
      expect(op.id, 'op-1');
      expect(op.kind, OpKind.push);
      expect(op.label, 'Pushing origin');
      expect(op.startedAt, startedAt);
      expect(op.repo, isNull);
      expect(op.status, OperationStatus.pending);
      expect(op.progress, isNull);
      expect(op.phase, '');
      expect(op.stderrTail, isEmpty);
      expect(op.finishedAt, isNull);
      expect(op.onCancel, isNull);
      expect(op.errorMessage, isNull);
    });

    test('carries a repo when provided', () {
      const repo = RepoLocation(RepoId('r1'), '/tmp/r', 'r');
      final op = RunningOperation(
        id: 'op-2',
        kind: OpKind.clone,
        label: 'Cloning',
        startedAt: startedAt,
        repo: repo,
      );
      expect(op.repo, repo);
    });
  });

  group('RunningOperation.copyWith', () {
    test('overrides provided fields and preserves identity fields', () {
      final finishedAt = DateTime.utc(2024, 1, 1, 12, 5);
      final updated = base().copyWith(
        status: OperationStatus.success,
        progress: 0.5,
        phase: 'Compressing',
        stderrTail: ['line'],
        finishedAt: finishedAt,
        errorMessage: 'note',
      );
      // Mutated fields.
      expect(updated.status, OperationStatus.success);
      expect(updated.progress, 0.5);
      expect(updated.phase, 'Compressing');
      expect(updated.stderrTail, ['line']);
      expect(updated.finishedAt, finishedAt);
      expect(updated.errorMessage, 'note');
      // Identity fields are always copied verbatim (not part of copyWith args).
      expect(updated.id, 'op-1');
      expect(updated.kind, OpKind.push);
      expect(updated.label, 'Pushing origin');
      expect(updated.startedAt, startedAt);
    });

    test('passing nothing yields an equal-by-props value', () {
      final op = base();
      final copy = op.copyWith();
      expect(copy, equals(op));
    });

    test('null arguments do not clear existing values (?? semantics)', () {
      final withProgress = base().copyWith(progress: 0.9, errorMessage: 'boom');
      // Explicit nulls fall through to the existing value due to `?? this.x`.
      final copy = withProgress.copyWith();
      expect(copy.progress, 0.9);
      expect(copy.errorMessage, 'boom');
    });
  });

  group('RunningOperation equality', () {
    test('props only include id/status/progress/phase/finishedAt', () {
      // Label, kind, repo, stderrTail and errorMessage are intentionally
      // excluded from props, so two ops differing only in those are equal.
      final a = base().copyWith(stderrTail: ['a'], errorMessage: 'x');
      final b = base().copyWith(stderrTail: ['b'], errorMessage: 'y');
      expect(a, equals(b));
    });

    test('differs when status differs', () {
      final a = base().copyWith(status: OperationStatus.running);
      final b = base().copyWith(status: OperationStatus.failed);
      expect(a, isNot(b));
    });

    test('differs when progress differs', () {
      final a = base().copyWith(progress: 0.1);
      final b = base().copyWith(progress: 0.2);
      expect(a, isNot(b));
    });
  });
}
