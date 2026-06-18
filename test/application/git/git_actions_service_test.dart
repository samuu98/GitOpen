import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/git/auth_failure_classifier.dart';
import 'package:gitopen/application/git/git_action_ports.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

const _initial = AuthProfile(
  id: 'init',
  host: 'github.com',
  username: 'a',
  spec: AuthSystemDefault(),
);
const _chosen = AuthProfile(
  id: 'chosen',
  host: 'github.com',
  username: 'b',
  spec: AuthSystemDefault(),
);

Stream<GitProgress> _ok() => Stream<GitProgress>.fromIterable(
      const [GitProgress(phase: 'done', rawLine: '', fraction: 1)],
    );
Stream<GitProgress> _err(String stderr) =>
    Stream<GitProgress>.error(StateError(stderr));

/// Fake write op: `fetch`/`push` return the next queued stream per call
/// (initial, then retry), so a test can script "fail, then succeed".
/// Arguments are recorded so routing (remote/branch/tags) can be asserted.
class _FakeWrite implements GitWriteOperations {
  _FakeWrite(this._streams);
  final List<Stream<GitProgress> Function()> _streams;
  int calls = 0;
  String? lastFetchRemote;
  String? lastPushRemote;
  String? lastPushBranch;
  bool? lastPushTags;
  bool? lastPushForce;
  String? lastDeleteRemoteRef;

  Stream<GitProgress> _next() {
    final s = _streams[calls < _streams.length ? calls : _streams.length - 1];
    calls++;
    return s();
  }

  @override
  Stream<GitProgress> fetch(
    RepoLocation r, {
    String? remote,
    bool all = false,
    AuthSpec? auth,
  }) {
    lastFetchRemote = remote;
    return _next();
  }

  @override
  Stream<GitProgress> push(
    RepoLocation r, {
    String? remote,
    String? branch,
    bool forceWithLease = false,
    bool pushTags = false,
    AuthSpec? auth,
  }) {
    lastPushRemote = remote;
    lastPushBranch = branch;
    lastPushTags = pushTags;
    lastPushForce = forceWithLease;
    return _next();
  }

  @override
  Stream<GitProgress> deleteRemoteBranch(
    RepoLocation r,
    String remoteRef, {
    AuthSpec? auth,
  }) {
    lastDeleteRemoteRef = remoteRef;
    return _next();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

class _FakePrompt implements AuthPrompt {
  _FakePrompt(this.result);
  final AuthProfile? result;
  int calls = 0;
  AuthFailureReason? lastReason;

  @override
  Future<AuthProfile?> forAccount(
    RepoLocation repo,
    AuthFailureReason reason,
  ) async {
    calls++;
    lastReason = reason;
    return result;
  }
}

class _FakeProgress implements ProgressSink {
  final List<String> events = [];
  int _n = 0;

  @override
  String start(
    OpKind kind,
    String label, {
    RepoLocation? repo,
    void Function()? onCancel,
  }) {
    final id = 'op${_n++}';
    events.add('start:$id');
    return id;
  }

  @override
  void progress(String id, double? fraction, String phase) =>
      events.add('progress:$id');
  @override
  void success(String id) => events.add('success:$id');
  @override
  void failure(String id, String message) => events.add('failure:$id');
}

void main() {
  final repo = RepoLocation(RepoId.newId(), 'unused', 'test');

  GitActionsService service(
    _FakeWrite write, {
    AuthProfile? initial = _initial,
  }) {
    return GitActionsService(
      write: write,
      resolveProfile: (_) async => initial,
      errorText: (e) => e.toString(),
    );
  }

  test('success: completes, no prompt, invalidates reads', () async {
    final write = _FakeWrite([_ok]);
    final prompt = _FakePrompt(null);
    final progress = _FakeProgress();

    final result =
        await service(write).fetch(repo, prompt: prompt, progress: progress);

    expect(result.outcome, ActionOutcome.success);
    expect(result.invalidate, contains(RepoDataScope.reads));
    expect(prompt.calls, 0);
    expect(write.calls, 1);
    expect(progress.events.any((e) => e.startsWith('success')), isTrue);
  });

  test('auth failure → prompt → retry succeeds', () async {
    final write = _FakeWrite([() => _err('fatal: Authentication failed'), _ok]);
    final prompt = _FakePrompt(_chosen);
    final progress = _FakeProgress();

    final result =
        await service(write).fetch(repo, prompt: prompt, progress: progress);

    expect(result.outcome, ActionOutcome.success);
    expect(prompt.calls, 1);
    expect(prompt.lastReason, AuthFailureReason.authRequired);
    expect(write.calls, 2); // initial + retry
  });

  test('auth failure → user cancels prompt → failed, no retry', () async {
    final write = _FakeWrite([() => _err('fatal: Authentication failed')]);
    final prompt = _FakePrompt(null);
    final progress = _FakeProgress();

    final result =
        await service(write).fetch(repo, prompt: prompt, progress: progress);

    expect(result.outcome, ActionOutcome.failed);
    expect(prompt.calls, 1);
    expect(write.calls, 1); // not retried
  });

  test('wrong-account failure classifies as wrongAccount', () async {
    final write = _FakeWrite([() => _err('remote: Repository not found'), _ok]);
    final prompt = _FakePrompt(_chosen);
    final progress = _FakeProgress();

    await service(write).fetch(repo, prompt: prompt, progress: progress);

    expect(prompt.lastReason, AuthFailureReason.wrongAccount);
  });

  test('non-auth failure → failed, no prompt', () async {
    final write = _FakeWrite([() => _err('fatal: not a git repository')]);
    final prompt = _FakePrompt(_chosen);
    final progress = _FakeProgress();

    final result =
        await service(write).fetch(repo, prompt: prompt, progress: progress);

    expect(result.outcome, ActionOutcome.failed);
    expect(prompt.calls, 0);
    expect(progress.events.any((e) => e.startsWith('failure')), isTrue);
  });

  test('deleteRemoteBranch streams to success and routes the ref', () async {
    final write = _FakeWrite([_ok]);
    final result = await service(write).deleteRemoteBranch(
      repo,
      'origin/feature',
      prompt: _FakePrompt(null),
      progress: _FakeProgress(),
    );

    expect(result.outcome, ActionOutcome.success);
    expect(write.lastDeleteRemoteRef, 'origin/feature');
  });

  test('deleteRemoteBranch retries after an auth failure', () async {
    final write =
        _FakeWrite([() => _err('fatal: Authentication failed'), _ok]);
    final prompt = _FakePrompt(_chosen);

    final result = await service(write).deleteRemoteBranch(
      repo,
      'origin/feature',
      prompt: prompt,
      progress: _FakeProgress(),
    );

    expect(result.outcome, ActionOutcome.success);
    expect(prompt.calls, 1);
    expect(write.calls, 2); // initial + retry
  });

  test('pushTag pushes the single tag ref to the named remote', () async {
    final write = _FakeWrite([_ok]);
    final prompt = _FakePrompt(null);
    final progress = _FakeProgress();

    final result = await service(write)
        .pushTag(repo, 'v1.2.3', prompt: prompt, progress: progress);

    expect(result.outcome, ActionOutcome.success);
    expect(write.lastPushRemote, 'origin');
    expect(write.lastPushBranch, 'v1.2.3');
    expect(write.lastPushTags, isFalse); // --tags would push EVERY tag
    expect(prompt.calls, 0);
  });

  test('fetchRemote fetches the named remote with auth-retry', () async {
    final write = _FakeWrite([() => _err('fatal: Authentication failed'), _ok]);
    final prompt = _FakePrompt(_chosen);
    final progress = _FakeProgress();

    final result = await service(write)
        .fetchRemote(repo, 'upstream', prompt: prompt, progress: progress);

    expect(result.outcome, ActionOutcome.success);
    expect(write.lastFetchRemote, 'upstream');
    expect(prompt.calls, 1);
    expect(write.calls, 2); // initial + retry
  });

  test('push forwards forceWithLease / branch / remote', () async {
    final write = _FakeWrite([_ok]);
    final prompt = _FakePrompt(null);
    final progress = _FakeProgress();

    final result = await service(write).push(
      repo,
      remote: 'origin',
      branch: 'feature/x',
      forceWithLease: true,
      prompt: prompt,
      progress: progress,
    );

    expect(result.outcome, ActionOutcome.success);
    expect(write.lastPushRemote, 'origin');
    expect(write.lastPushBranch, 'feature/x');
    expect(write.lastPushForce, isTrue);
    expect(write.lastPushTags, isFalse);
  });

  test('push --tags only', () async {
    final write = _FakeWrite([_ok]);
    final prompt = _FakePrompt(null);
    final progress = _FakeProgress();

    await service(write)
        .push(repo, pushTags: true, prompt: prompt, progress: progress);

    expect(write.lastPushTags, isTrue);
    expect(write.lastPushBranch, isNull);
  });
}
