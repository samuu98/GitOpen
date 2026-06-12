import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/git/auth_failure_classifier.dart';
import 'package:gitopen/application/git/git_action_ports.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git_lfs/git_lfs_operations.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

/// Pure orchestrator for Git LFS actions, mirroring [GitActionsService]:
/// simple mutations map a [GitResult] to a declarative [ActionResult];
/// the sync commands (fetch/pull/push) stream progress and run the same
/// prompt-and-retry loop on auth failures.
final class GitLfsService {
  GitLfsService({
    required GitLfsOperations lfs,
    required Future<AuthProfile?> Function(RepoLocation repo) resolveProfile,
    required String Function(Object error) errorText,
    AuthFailureClassifier classifier = const AuthFailureClassifier(),
  }) : _lfs = lfs,
       _resolveProfile = resolveProfile,
       _errorText = errorText,
       _classifier = classifier;

  final GitLfsOperations _lfs;
  final Future<AuthProfile?> Function(RepoLocation repo) _resolveProfile;
  final String Function(Object error) _errorText;
  final AuthFailureClassifier _classifier;

  /// `git lfs install --local`.
  Future<ActionResult> installLocal(RepoLocation repo) =>
      _simple('Git LFS install', _lfs.installLocal(repo));

  /// `git lfs track <pattern>`.
  Future<ActionResult> track(RepoLocation repo, String pattern) =>
      _simple('Git LFS track', _lfs.track(repo, pattern));

  /// `git lfs untrack <pattern>`.
  Future<ActionResult> untrack(RepoLocation repo, String pattern) =>
      _simple('Git LFS untrack', _lfs.untrack(repo, pattern));

  /// `git lfs fetch` with progress + auth-retry.
  Future<ActionResult> fetch(
    RepoLocation repo, {
    required AuthPrompt prompt,
    required ProgressSink progress,
  }) => _runStream(
    OpKind.fetch,
    'Git LFS fetch',
    repo,
    (auth) => _lfs.fetch(repo, auth: auth),
    prompt: prompt,
    progress: progress,
  );

  /// `git lfs pull` with progress + auth-retry.
  Future<ActionResult> pull(
    RepoLocation repo, {
    required AuthPrompt prompt,
    required ProgressSink progress,
  }) => _runStream(
    OpKind.pull,
    'Git LFS pull',
    repo,
    (auth) => _lfs.pull(repo, auth: auth),
    prompt: prompt,
    progress: progress,
  );

  /// `git lfs push origin` with progress + auth-retry.
  Future<ActionResult> push(
    RepoLocation repo, {
    required AuthPrompt prompt,
    required ProgressSink progress,
  }) => _runStream(
    OpKind.push,
    'Git LFS push',
    repo,
    (auth) => _lfs.push(repo, auth: auth),
    prompt: prompt,
    progress: progress,
  );

  /// Maps a plain LFS result to an [ActionResult]; failure carries a
  /// '`label` failed: …' message so call sites can never swallow it.
  Future<ActionResult> _simple(
    String label,
    Future<GitResult<void>> op,
  ) async {
    final result = await op;
    return switch (result) {
      GitSuccess() => const ActionResult(
        ActionOutcome.success,
        invalidate: {RepoDataScope.reads},
      ),
      GitFailure(:final message) => ActionResult(
        ActionOutcome.failed,
        invalidate: const {RepoDataScope.reads},
        message: '$label failed: $message',
        severity: MessageSeverity.error,
      ),
    };
  }

  /// Same shape as `GitActionsService._runStream`: drive the stream through
  /// [progress]; on an auth-classified failure ask [prompt] for an account
  /// and retry once per choice; the user cancelling ends the loop.
  Future<ActionResult> _runStream(
    OpKind kind,
    String label,
    RepoLocation repo,
    Stream<GitProgress> Function(AuthSpec? auth) streamFactory, {
    required AuthPrompt prompt,
    required ProgressSink progress,
    AuthProfile? profile,
    bool profileResolved = false,
  }) async {
    final id = progress.start(kind, label, repo: repo);
    final resolved = profileResolved ? profile : await _resolveProfile(repo);
    try {
      await for (final ev in streamFactory(resolved?.spec)) {
        progress.progress(id, ev.fraction, ev.phase);
      }
      progress.success(id);
      return const ActionResult.reads(ActionOutcome.success);
    } on Object catch (e) {
      // Classify ONLY the extracted error text — the full exception string
      // embeds the argv (with `Authorization`) and would false-positive.
      final reason = _classifier.classify(_errorText(e));
      if (reason != null) {
        progress.failure(
          id,
          reason == AuthFailureReason.wrongAccount
              ? 'Repository not visible to current account'
              : 'Authentication required',
        );
        final chosen = await prompt.forAccount(repo, reason);
        if (chosen == null) return const ActionResult(ActionOutcome.failed);
        return _runStream(
          kind,
          label,
          repo,
          streamFactory,
          prompt: prompt,
          progress: progress,
          profile: chosen,
          profileResolved: true,
        );
      }
      progress.failure(id, e.toString());
      return const ActionResult(ActionOutcome.failed);
    }
  }
}
