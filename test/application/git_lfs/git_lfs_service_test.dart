import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/git/auth_failure_classifier.dart';
import 'package:gitopen/application/git/git_action_ports.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git_lfs/git_lfs_models.dart';
import 'package:gitopen/application/git_lfs/git_lfs_operations.dart';
import 'package:gitopen/application/git_lfs/git_lfs_service.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

void main() {
  test('track returns success and invalidates reads', () async {
    final lfs = _FakeLfsOperations();
    final sut = GitLfsService(
      lfs: lfs,
      resolveProfile: (_) async => null,
      errorText: (e) => e.toString(),
    );

    final result = await sut.track(_repo, '*.bin');

    expect(result.outcome, ActionOutcome.success);
    expect(result.invalidate, contains(RepoDataScope.reads));
    expect(lfs.trackedPattern, '*.bin');
  });

  test('untrack failure surfaces the git error message', () async {
    final sut = GitLfsService(
      lfs: _FakeLfsOperations()..failSimple = true,
      resolveProfile: (_) async => null,
      errorText: (e) => e.toString(),
    );

    final result = await sut.untrack(_repo, '*.bin');

    expect(result.outcome, ActionOutcome.failed);
    expect(result.message, contains('boom'));
  });

  test('fetch drives progress sink', () async {
    final progress = _FakeProgressSink();
    final sut = GitLfsService(
      lfs: _FakeLfsOperations()
        ..progress = const GitProgress(
          phase: 'Downloading',
          rawLine: 'Downloading',
        ),
      resolveProfile: (_) async => null,
      errorText: (e) => e.toString(),
    );

    final result = await sut.fetch(
      _repo,
      prompt: _NoopAuthPrompt(),
      progress: progress,
    );

    expect(result.outcome, ActionOutcome.success);
    expect(progress.phases, contains('Downloading'));
  });

  test(
    'push auth failure prompts and retries with the chosen account',
    () async {
      final lfs = _FakeLfsOperations()
        ..syncErrors = ['Authentication failed for remote'];
      final prompt = _RecordingAuthPrompt();
      final result = await GitLfsService(
        lfs: lfs,
        resolveProfile: (_) async => null,
        errorText: (e) => e.toString(),
      ).push(_repo, prompt: prompt, progress: _FakeProgressSink());

      expect(prompt.askedReason, AuthFailureReason.authRequired);
      expect(result.outcome, ActionOutcome.success);
      expect(lfs.syncCalls, 2);
    },
  );
}

final _repo = RepoLocation(RepoId.newId(), 'unused', 'repo');

const _chosen = AuthProfile(
  id: 'chosen',
  host: 'github.com',
  username: 'b',
  spec: AuthSystemDefault(),
);

final class _FakeLfsOperations implements GitLfsOperations {
  String? trackedPattern;
  GitProgress? progress;
  bool failSimple = false;

  /// Errors thrown by successive sync calls (fetch/pull/push); once the
  /// list is exhausted the call succeeds. Lets a test script "fail with
  /// auth error, then succeed on retry".
  List<String> syncErrors = [];
  int syncCalls = 0;

  @override
  Future<GitLfsStatus> status(RepoLocation repo) async => const GitLfsStatus(
    isInstalled: true,
    version: '3.6.1',
    isRepoConfigured: true,
    hasAttributes: true,
  );

  @override
  Future<List<GitLfsTrackedPattern>> trackedPatterns(RepoLocation repo) async =>
      const [];

  @override
  Future<List<GitLfsFile>> files(RepoLocation repo) async => const [];

  @override
  Future<GitResult<void>> installLocal(RepoLocation repo) async => failSimple
      ? const GitFailure(GitErrorKind.other, 'boom')
      : const GitSuccess(null);

  @override
  Future<GitResult<void>> track(RepoLocation repo, String pattern) async {
    if (failSimple) return const GitFailure(GitErrorKind.other, 'boom');
    trackedPattern = pattern;
    return const GitSuccess(null);
  }

  @override
  Future<GitResult<void>> untrack(RepoLocation repo, String pattern) async =>
      failSimple
      ? const GitFailure(GitErrorKind.other, 'boom')
      : const GitSuccess(null);

  @override
  Stream<GitProgress> fetch(RepoLocation repo, {AuthSpec? auth}) async* {
    syncCalls++;
    if (syncErrors.isNotEmpty) {
      throw StateError(syncErrors.removeAt(0));
    }
    final event = progress;
    if (event != null) yield event;
  }

  @override
  Stream<GitProgress> pull(RepoLocation repo, {AuthSpec? auth}) => fetch(repo);

  @override
  Stream<GitProgress> push(RepoLocation repo, {AuthSpec? auth}) => fetch(repo);
}

final class _FakeProgressSink implements ProgressSink {
  final phases = <String>[];

  @override
  String start(
    OpKind kind,
    String label, {
    RepoLocation? repo,
    void Function()? onCancel,
  }) =>
      'op';

  @override
  void progress(String id, double? fraction, String phase) {
    phases.add(phase);
  }

  @override
  void success(String id) {}

  @override
  void failure(String id, String message) {}
}

final class _NoopAuthPrompt implements AuthPrompt {
  @override
  Future<AuthProfile?> forAccount(
    RepoLocation repo,
    AuthFailureReason reason,
  ) async => null;
}

final class _RecordingAuthPrompt implements AuthPrompt {
  AuthFailureReason? askedReason;

  @override
  Future<AuthProfile?> forAccount(
    RepoLocation repo,
    AuthFailureReason reason,
  ) async {
    askedReason = reason;
    return _chosen;
  }
}
