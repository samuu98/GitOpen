import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

/// Fake write op for the local (non-streaming) actions: returns canned
/// GitResults so the mapping to [ActionResult] can be asserted without git.
class _FakeWrite implements GitWriteOperations {
  GitResult<MergeOutcome> mergeResult =
      const GitSuccess<MergeOutcome>(MergeUpToDate());
  GitResult<CherryPickOutcome> cherryResult =
      const GitSuccess<CherryPickOutcome>(CherryPickConflict(['x.txt']));
  GitResult<void> resetResult = const GitSuccess<void>(null);
  GitResult<void> voidResult = const GitSuccess<void>(null);
  GitResult<CommitSha> shaResult = GitSuccess<CommitSha>(CommitSha('abcdef1'));
  GitResult<RebaseOutcome> interactiveResult =
      const GitSuccess<RebaseOutcome>(RebaseUpToDate());

  @override
  Future<GitResult<MergeOutcome>> merge(
    RepoLocation r,
    String ref, {
    MergeStrategy strategy = MergeStrategy.defaultStrategy,
  }) async =>
      mergeResult;

  @override
  Future<GitResult<CherryPickOutcome>> cherryPick(
    RepoLocation r,
    CommitSha sha,
  ) async =>
      cherryResult;

  @override
  Future<GitResult<void>> reset(
    RepoLocation r,
    CommitSha to,
    ResetMode mode,
  ) async =>
      resetResult;

  @override
  Future<GitResult<void>> checkout(
    RepoLocation r,
    String ref, {
    bool force = false,
  }) async =>
      voidResult;

  @override
  Future<GitResult<void>> createBranch(
    RepoLocation r,
    String name, {
    CommitSha? at,
    bool checkout = false,
  }) async =>
      voidResult;

  @override
  Future<GitResult<void>> stashPop(RepoLocation r, int index) async =>
      voidResult;

  @override
  Future<GitResult<void>> rebaseAbort(RepoLocation r) async => voidResult;

  @override
  Future<GitResult<CommitSha>> mergeContinue(RepoLocation r) async =>
      shaResult;

  @override
  Future<GitResult<RebaseOutcome>> interactiveRebase(
    RepoLocation r,
    CommitSha onto,
    List<RebaseTodoEntry> plan,
  ) async =>
      interactiveResult;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

void main() {
  final repo = RepoLocation(RepoId.newId(), 'unused', 'test');
  final sha = CommitSha('abcdef1');
  const strategy = MergeStrategy.defaultStrategy;

  GitActionsService service(_FakeWrite write) => GitActionsService(
        write: write,
        resolveProfile: (_) async => null,
        errorText: (e) => e.toString(),
      );

  test('merge success → success, invalidates reads+repoState, no message',
      () async {
    final write = _FakeWrite()
      ..mergeResult = const GitSuccess<MergeOutcome>(MergeUpToDate());
    final r = await service(write).merge(repo, 'feature', strategy);
    expect(r.outcome, ActionOutcome.success);
    expect(
      r.invalidate,
      unorderedEquals({RepoDataScope.reads, RepoDataScope.repoState}),
    );
    expect(r.message, isNull);
  });

  test('merge conflict → conflict outcome + count message', () async {
    final write = _FakeWrite()
      ..mergeResult =
          const GitSuccess<MergeOutcome>(MergeConflict(['a.txt', 'b.txt']));
    final r = await service(write).merge(repo, 'feature', strategy);
    expect(r.outcome, ActionOutcome.conflict);
    expect(r.message, contains('2 file(s)'));
    expect(r.invalidate, contains(RepoDataScope.repoState));
  });

  test('merge failure → failed + "Merge failed:" message', () async {
    final write = _FakeWrite()
      ..mergeResult =
          const GitFailure<MergeOutcome>(GitErrorKind.conflict, 'boom', 'boom');
    final r = await service(write).merge(repo, 'feature', strategy);
    expect(r.outcome, ActionOutcome.failed);
    expect(r.message, contains('Merge failed'));
  });

  test('cherryPick conflict → conflict + labelled message', () async {
    final write = _FakeWrite()
      ..cherryResult =
          const GitSuccess<CherryPickOutcome>(CherryPickConflict(['c.txt']));
    final r = await service(write).cherryPick(repo, sha);
    expect(r.outcome, ActionOutcome.conflict);
    expect(r.message, contains('Cherry-pick conflict'));
  });

  test('reset success → success', () async {
    final write = _FakeWrite()..resetResult = const GitSuccess<void>(null);
    final r = await service(write).reset(repo, sha, ResetMode.hard);
    expect(r.outcome, ActionOutcome.success);
  });

  test('reset failure → failed + "Reset failed:" message', () async {
    final write = _FakeWrite()
      ..resetResult =
          const GitFailure<void>(GitErrorKind.other, 'nope', 'nope');
    final r = await service(write).reset(repo, sha, ResetMode.hard);
    expect(r.outcome, ActionOutcome.failed);
    expect(r.message, contains('Reset failed'));
  });

  test('checkout success → success, invalidates reads only, no message',
      () async {
    final write = _FakeWrite()..voidResult = const GitSuccess<void>(null);
    final r = await service(write).checkout(repo, 'feature');
    expect(r.outcome, ActionOutcome.success);
    expect(r.invalidate, {RepoDataScope.reads});
    expect(r.message, isNull);
  });

  test('checkout failure → failed + "Checkout failed:" error message',
      () async {
    final write = _FakeWrite()
      ..voidResult = const GitFailure<void>(
          GitErrorKind.other, 'local changes', 'local changes');
    final r = await service(write).checkout(repo, 'feature');
    expect(r.outcome, ActionOutcome.failed);
    expect(r.message, contains('Checkout failed'));
    expect(r.severity, MessageSeverity.error);
  });

  test('createBranch failure → labelled error message', () async {
    final write = _FakeWrite()
      ..voidResult =
          const GitFailure<void>(GitErrorKind.other, 'exists', 'exists');
    final r = await service(write).createBranch(repo, 'feature');
    expect(r.outcome, ActionOutcome.failed);
    expect(r.message, contains('Create branch failed'));
  });

  test('stashPop failure → labelled error message', () async {
    final write = _FakeWrite()
      ..voidResult =
          const GitFailure<void>(GitErrorKind.conflict, 'clash', 'clash');
    final r = await service(write).stashPop(repo, 0);
    expect(r.outcome, ActionOutcome.failed);
    expect(r.message, contains('Stash pop failed'));
  });

  test('mergeContinue success → invalidates reads+repoState', () async {
    final write = _FakeWrite()
      ..shaResult = GitSuccess<CommitSha>(CommitSha('abcdef1'));
    final r = await service(write).mergeContinue(repo);
    expect(r.outcome, ActionOutcome.success);
    expect(
      r.invalidate,
      unorderedEquals({RepoDataScope.reads, RepoDataScope.repoState}),
    );
  });

  test('rebaseAbort failure → labelled error message', () async {
    final write = _FakeWrite()
      ..voidResult =
          const GitFailure<void>(GitErrorKind.other, 'no rebase', 'no rebase');
    final r = await service(write).rebaseAbort(repo);
    expect(r.outcome, ActionOutcome.failed);
    expect(r.message, contains('Abort rebase failed'));
  });

  test('interactiveRebase conflict → conflict outcome + count message',
      () async {
    final write = _FakeWrite()
      ..interactiveResult =
          const GitSuccess<RebaseOutcome>(RebaseConflict(['a.txt', 'b.txt']));
    final r = await service(write)
        .interactiveRebase(repo, sha, const <RebaseTodoEntry>[]);
    expect(r.outcome, ActionOutcome.conflict);
    expect(r.message, contains('2 file(s)'));
    expect(
      r.invalidate,
      unorderedEquals({RepoDataScope.reads, RepoDataScope.repoState}),
    );
  });

  test('interactiveRebase failure → failed + "Rebase failed:" message',
      () async {
    final write = _FakeWrite()
      ..interactiveResult = const GitFailure<RebaseOutcome>(
          GitErrorKind.other, 'dirty tree', 'dirty tree');
    final r = await service(write)
        .interactiveRebase(repo, sha, const <RebaseTodoEntry>[]);
    expect(r.outcome, ActionOutcome.failed);
    expect(r.message, contains('Rebase failed'));
  });
}
