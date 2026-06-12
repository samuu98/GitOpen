import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/git/git_action_ports.dart';
import 'package:gitopen/application/git/git_actions_service.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/git/git_action_bridges.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Exposes [LfsActionsController] — the single UI entry point for LFS actions.
final lfsActionsControllerProvider = Provider<LfsActionsController>(
  LfsActionsController.new,
);

/// Thin UI adapter over the pure `GitLfsService`, mirroring
/// `GitActionsController`: supplies the auth-prompt and progress-sink
/// bridges, then applies the returned [ActionResult] by invalidating the
/// LFS read providers and showing any message as a snackbar.
class LfsActionsController {
  LfsActionsController(this._ref);
  final Ref _ref;

  /// `git lfs install --local`.
  Future<ActionResult> installLocal(BuildContext context, RepoLocation repo) =>
      _runLocal(
        context,
        repo,
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
    () => _ref.read(gitLfsServiceProvider).untrack(repo, pattern),
  );

  /// `git lfs fetch` with progress + auth-retry.
  Future<ActionResult> fetch(BuildContext context, RepoLocation repo) => _run(
    context,
    repo,
    (prompt, progress) => _ref
        .read(gitLfsServiceProvider)
        .fetch(repo, prompt: prompt, progress: progress),
  );

  /// `git lfs pull` with progress + auth-retry.
  Future<ActionResult> pull(BuildContext context, RepoLocation repo) => _run(
    context,
    repo,
    (prompt, progress) => _ref
        .read(gitLfsServiceProvider)
        .pull(repo, prompt: prompt, progress: progress),
  );

  /// `git lfs push origin` with progress + auth-retry.
  Future<ActionResult> push(BuildContext context, RepoLocation repo) => _run(
    context,
    repo,
    (prompt, progress) => _ref
        .read(gitLfsServiceProvider)
        .push(repo, prompt: prompt, progress: progress),
  );

  Future<ActionResult> _run(
    BuildContext context,
    RepoLocation repo,
    Future<ActionResult> Function(AuthPrompt prompt, ProgressSink progress) op,
  ) async {
    final result = await op(
      DialogAuthPrompt(context, _ref),
      OperationsProgressSink(_ref),
    );
    _invalidate(repo);
    final message = result.message;
    if (message != null && context.mounted) {
      _showSnack(context, message, result.severity);
    }
    return result;
  }

  Future<ActionResult> _runLocal(
    BuildContext context,
    RepoLocation repo,
    Future<ActionResult> Function() op,
  ) async {
    final result = await op();
    _invalidate(repo);
    final message = result.message;
    if (message != null && context.mounted) {
      _showSnack(context, message, result.severity);
    }
    return result;
  }

  void _invalidate(RepoLocation repo) {
    // Needs no context; runs whether or not the caller is still mounted.
    _ref
      ..invalidate(gitLfsStatusProvider(repo))
      ..invalidate(gitLfsTrackedPatternsProvider(repo))
      ..invalidate(gitLfsFilesProvider(repo))
      ..invalidate(repoStatusProvider(repo));
  }

  void _showSnack(
    BuildContext context,
    String message,
    MessageSeverity? severity,
  ) {
    final palette = AppPalette.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: severity == MessageSeverity.error
            ? palette.accentErr
            : null,
      ),
    );
  }
}
