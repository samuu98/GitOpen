import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gitopen/application/git/git_action_ports.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/git/action_runner.dart';
import 'package:gitopen/ui/git/git_action_bridges.dart';
import 'package:gitopen/ui/operations/action_feedback.dart';

/// Exposes [LfsActionsController] — the single UI entry point for LFS actions.
final lfsActionsControllerProvider = Provider<LfsActionsController>(
  LfsActionsController.new,
);

final lfsSyncBusyProvider = StateProvider.family<bool, RepoLocation>(
  (ref, repo) => false,
);

/// Thin UI adapter over the pure `GitLfsService`, mirroring
/// `GitActionsController`: supplies the auth-prompt and progress-sink
/// bridges, then waits for affected views before clearing pending state.
class LfsActionsController {
  LfsActionsController(this._ref);
  final Ref _ref;

  /// `git lfs install --local`.
  Future<ActionResult> installLocal(BuildContext context, RepoLocation repo) =>
      _runLocal(
        context,
        repo,
        'install',
        () => _ref.read(gitLfsServiceProvider).installLocal(repo),
      );

  /// `git lfs track <pattern>`.
  Future<ActionResult> track(
    BuildContext context,
    RepoLocation repo,
    String pattern,
  ) => _runLocal(
    context,
    repo,
    'track:$pattern',
    () => _ref.read(gitLfsServiceProvider).track(repo, pattern),
  );

  /// `git lfs untrack <pattern>`.
  Future<ActionResult> untrack(
    BuildContext context,
    RepoLocation repo,
    String pattern,
  ) => _runLocal(
    context,
    repo,
    'untrack:$pattern',
    () => _ref.read(gitLfsServiceProvider).untrack(repo, pattern),
  );

  /// `git lfs fetch` with progress + auth-retry.
  Future<ActionResult> fetch(BuildContext context, RepoLocation repo) => _run(
    context,
    repo,
    'fetch',
    (prompt, progress) => _ref
        .read(gitLfsServiceProvider)
        .fetch(repo, prompt: prompt, progress: progress),
  );

  /// `git lfs pull` with progress + auth-retry.
  Future<ActionResult> pull(BuildContext context, RepoLocation repo) => _run(
    context,
    repo,
    'pull',
    (prompt, progress) => _ref
        .read(gitLfsServiceProvider)
        .pull(repo, prompt: prompt, progress: progress),
  );

  /// `git lfs push origin` with progress + auth-retry.
  Future<ActionResult> push(BuildContext context, RepoLocation repo) => _run(
    context,
    repo,
    'push',
    (prompt, progress) => _ref
        .read(gitLfsServiceProvider)
        .push(repo, prompt: prompt, progress: progress),
  );

  Future<ActionResult> _run(
    BuildContext context,
    RepoLocation repo,
    String key,
    Future<ActionResult> Function(AuthPrompt prompt, ProgressSink progress) op,
  ) => _execute(
    repo,
    key,
    () => op(
      DialogAuthPrompt(context, _ref),
      OperationsProgressSink(_ref),
    ),
  );

  Future<ActionResult> _runLocal(
    BuildContext context,
    RepoLocation repo,
    String key,
    Future<ActionResult> Function() op,
  ) => _execute(repo, key, op);

  Future<ActionResult> _execute(
    RepoLocation repo,
    String key,
    Future<ActionResult> Function() op,
  ) async {
    if (_ref.read(lfsSyncBusyProvider(repo))) {
      return const ActionResult(ActionOutcome.failed);
    }
    _ref.read(lfsSyncBusyProvider(repo).notifier).state = true;
    try {
      final run = await _ref
          .read(actionRunnerProvider)
          .runAndRefresh<ActionResult>(
            key: 'lfs:$key',
            repo: repo,
            scopes: const {
              RefreshScope.status,
              RefreshScope.workingCopy,
              RefreshScope.lfsPanel,
            },
            action: op,
            failed: (value) => value.outcome == ActionOutcome.failed,
            operationId: (value) => value.operationId,
          );
      final result = run.value;
      if (result == null) return const ActionResult(ActionOutcome.failed);
      final message = result.message;
      // A refresh failure is the runner's message, with its own Retry.
      if (message != null &&
          run.status != ActionRunStatus.stale &&
          run.status != ActionRunStatus.refreshFailed) {
        final feedback = _ref.read(actionFeedbackProvider);
        if (result.severity == MessageSeverity.error) {
          feedback.showActionFailure(message);
        } else {
          feedback.showActionSuccess(message);
        }
      }
      return result;
    } finally {
      if (_ref.mounted) {
        _ref.read(lfsSyncBusyProvider(repo).notifier).state = false;
      }
    }
  }
}
