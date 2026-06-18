import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/git/auth_failure_classifier.dart';
import 'package:gitopen/application/git/git_action_ports.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

final class _FakeWrite implements GitWriteOperations {
  final calls = <String>[];
  bool failFetch = false;

  @override
  Stream<GitProgress> fetchRefspec(
    RepoLocation r,
    String remote,
    String refspec, {
    AuthSpec? auth,
  }) {
    calls.add('fetch $remote $refspec');
    if (failFetch) {
      return Stream.error(Exception('fatal: could not read from remote'));
    }
    return const Stream.empty();
  }

  @override
  Future<GitResult<void>> checkout(
    RepoLocation r,
    String ref, {
    bool force = false,
  }) async {
    calls.add('checkout $ref');
    return const GitSuccess<void>(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _NoPrompt implements AuthPrompt {
  @override
  Future<AuthProfile?> forAccount(
    RepoLocation repo,
    AuthFailureReason reason,
  ) async => null;
}

final class _NullSink implements ProgressSink {
  @override
  String start(
    OpKind kind,
    String label, {
    RepoLocation? repo,
    void Function()? onCancel,
  }) =>
      'op';

  @override
  void progress(String id, double? fraction, String phase) {}

  @override
  void success(String id) {}

  @override
  void failure(String id, String message) {}
}

void main() {
  final repo = RepoLocation(RepoId.newId(), 'unused', 'repo');

  GitActionsService service(_FakeWrite write) => GitActionsService(
    write: write,
    resolveProfile: (_) async => null,
    errorText: (e) => e.toString(),
  );

  test(
    'checkoutPullRequest force-fetches pull/<n>/head then checks out',
    () async {
      final write = _FakeWrite();
      final result = await service(write).checkoutPullRequest(
        repo,
        42,
        prompt: _NoPrompt(),
        progress: _NullSink(),
      );
      expect(result.outcome, ActionOutcome.success);
      expect(write.calls, [
        'fetch origin +pull/42/head:refs/heads/pr/42',
        'checkout pr/42',
      ]);
    },
  );

  test('a failed fetch stops before checkout', () async {
    final write = _FakeWrite()..failFetch = true;
    final result = await service(write).checkoutPullRequest(
      repo,
      42,
      prompt: _NoPrompt(),
      progress: _NullSink(),
    );
    expect(result.outcome, ActionOutcome.failed);
    expect(write.calls, ['fetch origin +pull/42/head:refs/heads/pr/42']);
  });
}
