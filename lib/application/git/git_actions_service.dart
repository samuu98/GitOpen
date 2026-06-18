import 'dart:async';

import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/git/auth_failure_classifier.dart';
import 'package:gitopen/application/git/git_action_ports.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';

/// How an action finished, from the caller's point of view.
enum ActionOutcome {
  /// The operation completed cleanly.
  success,

  /// The operation paused on a conflict the user must resolve.
  conflict,

  /// The operation could not complete (already surfaced to the user via the
  /// progress sink / a message).
  failed,
}

/// Which cached repo data an action invalidated, so the UI adapter can refresh
/// exactly the right providers (kept declarative to keep the service pure).
enum RepoDataScope {
  /// The read-ops cache (`gitReadOperationsProvider`) — commits, refs, status…
  reads,

  /// The in-progress-op detection (`repoStateProvider`) — merge/rebase state.
  repoState,
}

/// Severity of a user-facing message attached to an [ActionResult].
enum MessageSeverity {
  /// Neutral information.
  info,

  /// A successful outcome worth confirming.
  success,

  /// An error the user should notice.
  error,
}

/// The declarative result of a git action: what happened, what to invalidate,
/// and an optional message for the UI adapter to surface.
final class ActionResult {
  const ActionResult(
    this.outcome, {
    this.invalidate = const {},
    this.message,
    this.severity,
  });

  /// Convenience for a clean success that invalidated the read cache.
  const ActionResult.reads(this.outcome)
    : invalidate = const {RepoDataScope.reads},
      message = null,
      severity = null;

  /// What happened.
  final ActionOutcome outcome;

  /// Repo data the action changed; the UI adapter invalidates the mapped
  /// providers.
  final Set<RepoDataScope> invalidate;

  /// Optional user-facing message (the adapter shows it as a snackbar).
  final String? message;

  /// Severity of [message], when present.
  final MessageSeverity? severity;
}

/// Pure application-layer orchestrator for git actions.
///
/// Owns the sequencing every UI call site used to duplicate: drive the op
/// through a [ProgressSink], classify failures, run the auth-retry loop via an
/// [AuthPrompt], and hand back a declarative [ActionResult] (what to invalidate
/// + any message). It depends only on the application interfaces and injected
/// ports — no Flutter, no `dart:io`, no infrastructure — so it is unit-testable
/// with fakes. The composition root injects `errorText` (the only code that
/// knows how to read git's stderr off a thrown infrastructure exception).
final class GitActionsService {
  GitActionsService({
    required GitWriteOperations write,
    required Future<AuthProfile?> Function(RepoLocation repo) resolveProfile,
    required String Function(Object error) errorText,
    AuthFailureClassifier classifier = const AuthFailureClassifier(),
    LoggerPort? log,
  }) : _write = write,
       _resolveProfile = resolveProfile,
       _errorText = errorText,
       _classifier = classifier,
       _log = log;

  final GitWriteOperations _write;
  final Future<AuthProfile?> Function(RepoLocation repo) _resolveProfile;
  final String Function(Object error) _errorText;
  final AuthFailureClassifier _classifier;
  final LoggerPort? _log;

  /// `git fetch` with progress + auth-retry.
  Future<ActionResult> fetch(
    RepoLocation repo, {
    required AuthPrompt prompt,
    required ProgressSink progress,
  }) {
    return _runStream(
      OpKind.fetch,
      'Fetching origin',
      repo,
      (auth) => _write.fetch(repo, auth: auth),
      prompt: prompt,
      progress: progress,
    );
  }

  /// `git pull` (with the caller-chosen [strategy]) with progress + auth-retry.
  Future<ActionResult> pull(
    RepoLocation repo,
    PullStrategy strategy, {
    required AuthPrompt prompt,
    required ProgressSink progress,
  }) {
    return _runStream(
      OpKind.pull,
      'Pulling',
      repo,
      (auth) => _write.pull(repo, strategy, auth: auth),
      prompt: prompt,
      progress: progress,
    );
  }

  /// `git push` with progress + auth-retry. The optional knobs map straight
  /// onto the write op: [remote]+[branch] push one ref, [forceWithLease]
  /// adds --force-with-lease, [pushTags] adds --tags.
  Future<ActionResult> push(
    RepoLocation repo, {
    required AuthPrompt prompt,
    required ProgressSink progress,
    String? remote,
    String? branch,
    bool forceWithLease = false,
    bool pushTags = false,
  }) {
    final label = forceWithLease
        ? 'Force-pushing'
        : pushTags
        ? 'Pushing tags'
        : branch != null
        ? 'Pushing $branch'
        : 'Pushing';
    return _runStream(
      OpKind.push,
      label,
      repo,
      (auth) => _write.push(
        repo,
        remote: remote,
        branch: branch,
        forceWithLease: forceWithLease,
        pushTags: pushTags,
        auth: auth,
      ),
      prompt: prompt,
      progress: progress,
    );
  }

  /// `git push <remote> <tag>` — pushes exactly one tag ref, with progress +
  /// auth-retry.
  Future<ActionResult> pushTag(
    RepoLocation repo,
    String tagName, {
    required AuthPrompt prompt,
    required ProgressSink progress,
    String remote = 'origin',
  }) {
    return _runStream(
      OpKind.push,
      'Pushing tag $tagName',
      repo,
      (auth) => _write.push(repo, remote: remote, branch: tagName, auth: auth),
      prompt: prompt,
      progress: progress,
    );
  }

  /// `git push <remote> --delete <branch>` — deletes [remoteRef]
  /// (`<remote>/<branch>`) on the server, with progress + auth-retry.
  Future<ActionResult> deleteRemoteBranch(
    RepoLocation repo,
    String remoteRef, {
    required AuthPrompt prompt,
    required ProgressSink progress,
  }) {
    return _runStream(
      OpKind.push,
      'Deleting $remoteRef',
      repo,
      (auth) => _write.deleteRemoteBranch(repo, remoteRef, auth: auth),
      prompt: prompt,
      progress: progress,
    );
  }

  /// `git fetch <remote>` with progress + auth-retry.
  Future<ActionResult> fetchRemote(
    RepoLocation repo,
    String remote, {
    required AuthPrompt prompt,
    required ProgressSink progress,
  }) {
    return _runStream(
      OpKind.fetch,
      'Fetching $remote',
      repo,
      (auth) => _write.fetch(repo, remote: remote, auth: auth),
      prompt: prompt,
      progress: progress,
    );
  }

  /// Materialises GitHub PR [number] as the local branch `pr/<number>`
  /// (forced fetch of `pull/<number>/head`) and checks it out. The fetch has
  /// progress + auth-retry; a fetch failure stops before the checkout.
  Future<ActionResult> checkoutPullRequest(
    RepoLocation repo,
    int number, {
    required AuthPrompt prompt,
    required ProgressSink progress,
  }) async {
    final branch = 'pr/$number';
    final fetched = await _runStream(
      OpKind.fetch,
      'Fetching PR #$number',
      repo,
      (auth) => _write.fetchRefspec(
        repo,
        'origin',
        '+pull/$number/head:refs/heads/$branch',
        auth: auth,
      ),
      prompt: prompt,
      progress: progress,
    );
    if (fetched.outcome != ActionOutcome.success) return fetched;
    return _simple('Checkout', _write.checkout(repo, branch));
  }

  // ---- Local (non-streaming) actions ------------------------------------
  // No auth / progress streaming; each maps the write op's GitResult to a
  // declarative ActionResult. Conflict-bearing ops report
  // ActionOutcome.conflict so the UI surfaces the conflicts panel.

  /// Invalidation set for local actions: refresh reads + in-progress state.
  static const Set<RepoDataScope> _localScope = {
    RepoDataScope.reads,
    RepoDataScope.repoState,
  };

  /// `git merge <ref>` with the given [strategy].
  Future<ActionResult> merge(
    RepoLocation repo,
    String ref,
    MergeStrategy strategy,
  ) async => _conflictable(
    await _write.merge(repo, ref, strategy: strategy),
    'Merge',
    (o) => o is MergeConflict ? o.conflictedPaths : null,
  );

  /// `git rebase <upstream>`.
  Future<ActionResult> rebase(RepoLocation repo, String upstream) async =>
      _conflictable(
        await _write.rebase(repo, upstream),
        'Rebase',
        (o) => o is RebaseConflict ? o.conflictedPaths : null,
      );

  /// `git cherry-pick <sha>`.
  Future<ActionResult> cherryPick(RepoLocation repo, CommitSha sha) async =>
      _conflictable(
        await _write.cherryPick(repo, sha),
        'Cherry-pick',
        (o) => o is CherryPickConflict ? o.conflictedPaths : null,
      );

  /// `git revert <sha>`.
  Future<ActionResult> revert(RepoLocation repo, CommitSha sha) async =>
      _conflictable(
        await _write.revert(repo, sha),
        'Revert',
        (o) => o is RevertConflict ? o.conflictedPaths : null,
      );

  /// `git reset --<mode>` to [to].
  Future<ActionResult> reset(
    RepoLocation repo,
    CommitSha to,
    ResetMode mode,
  ) => _simple('Reset', _write.reset(repo, to, mode), invalidate: _localScope);

  /// `git rebase -i` driven by a scripted [plan] (no editor). Conflict-bearing,
  /// like [rebase].
  Future<ActionResult> interactiveRebase(
    RepoLocation repo,
    CommitSha onto,
    List<RebaseTodoEntry> plan,
  ) async => _conflictable(
    await _write.interactiveRebase(repo, onto, plan),
    'Rebase',
    (o) => o is RebaseConflict ? o.conflictedPaths : null,
  );

  /// Rewrites [sha]'s commit message via a scripted `rebase -i` (reword).
  /// Conflict-bearing like [rebase].
  Future<ActionResult> rewordCommit(
    RepoLocation repo,
    CommitSha sha,
    String message,
  ) async => _conflictable(
    await _write.rewordCommit(repo, sha, message),
    'Reword',
    (o) => o is RebaseConflict ? o.conflictedPaths : null,
  );

  /// Starts a rebase paused at [sha] so the user can amend it; the in-progress
  /// panel then offers Continue/Abort.
  Future<ActionResult> editAtCommit(RepoLocation repo, CommitSha sha) async {
    final result = await _write.editAtCommit(repo, sha);
    return switch (result) {
      GitSuccess(value: RebaseStoppedForEdit()) => const ActionResult(
        ActionOutcome.success,
        invalidate: _localScope,
        message:
            'Rebase paused at the commit — amend it, then Continue '
            'in the panel below.',
        severity: MessageSeverity.info,
      ),
      GitSuccess(value: final RebaseConflict c) => ActionResult(
        ActionOutcome.conflict,
        invalidate: _localScope,
        message:
            'Edit conflict in ${c.conflictedPaths.length} file(s). '
            'Resolve in the conflicts panel below.',
        severity: MessageSeverity.error,
      ),
      GitSuccess() => const ActionResult(
        ActionOutcome.success,
        invalidate: _localScope,
      ),
      GitFailure(:final message) => ActionResult(
        ActionOutcome.failed,
        invalidate: _localScope,
        message: 'Edit failed: $message',
        severity: MessageSeverity.error,
      ),
    };
  }

  // ---- Ref / stash CRUD ---------------------------------------------------
  // Pure bookkeeping ops: success refreshes reads; failure surfaces the git
  // error (these call sites used to ignore it).

  /// `git checkout <ref>`.
  Future<ActionResult> checkout(RepoLocation repo, String ref) =>
      _simple('Checkout', _write.checkout(repo, ref));

  /// `git checkout --track <remoteRef>` — checks a remote branch out as a
  /// new local tracking branch.
  Future<ActionResult> checkoutTrack(RepoLocation repo, String remoteRef) =>
      _simple('Checkout', _write.checkoutTrack(repo, remoteRef));

  /// `git branch <name>` (optionally at [at], optionally checked out).
  Future<ActionResult> createBranch(
    RepoLocation repo,
    String name, {
    CommitSha? at,
    bool checkout = false,
  }) => _simple(
    'Create branch',
    _write.createBranch(repo, name, at: at, checkout: checkout),
  );

  /// `git branch -m <old> <new>`.
  Future<ActionResult> renameBranch(
    RepoLocation repo,
    String oldName,
    String newName,
  ) => _simple('Rename branch', _write.renameBranch(repo, oldName, newName));

  /// `git branch -d/-D <name>`.
  Future<ActionResult> deleteBranch(
    RepoLocation repo,
    String name, {
    bool force = false,
  }) => _simple('Delete branch', _write.deleteBranch(repo, name, force: force));

  /// `git branch --set-upstream-to=<upstream> <branch>`.
  Future<ActionResult> setUpstream(
    RepoLocation repo,
    String branch,
    String upstream,
  ) => _simple('Set upstream', _write.setUpstream(repo, branch, upstream));

  /// `git tag <name>` (optionally annotated, optionally at [at]).
  Future<ActionResult> createTag(
    RepoLocation repo,
    String name, {
    CommitSha? at,
    String? message,
  }) => _simple(
    'Create tag',
    _write.createTag(repo, name, at: at, message: message),
  );

  /// `git tag -d <name>`.
  Future<ActionResult> deleteTag(RepoLocation repo, String name) =>
      _simple('Delete tag', _write.deleteTag(repo, name));

  /// `git stash push`.
  Future<ActionResult> stashSave(
    RepoLocation repo,
    String message, {
    bool includeUntracked = false,
    List<String> paths = const [],
  }) => _simple(
    'Stash',
    _write.stashSave(
      repo,
      message,
      includeUntracked: includeUntracked,
      paths: paths,
    ),
  );

  /// `git stash apply stash@{index}`.
  Future<ActionResult> stashApply(RepoLocation repo, int index) =>
      _simple('Stash apply', _write.stashApply(repo, index));

  /// `git stash pop stash@{index}`.
  Future<ActionResult> stashPop(RepoLocation repo, int index) =>
      _simple('Stash pop', _write.stashPop(repo, index));

  /// `git stash drop stash@{index}`.
  Future<ActionResult> stashDrop(RepoLocation repo, int index) =>
      _simple('Stash drop', _write.stashDrop(repo, index));

  /// Resolves a conflicted file by taking one side wholesale.
  Future<ActionResult> takeConflictSide(
    RepoLocation repo,
    String path, {
    required bool ours,
  }) => _simple(
    'Resolve',
    _write.takeConflictSide(repo, path, ours: ours),
    invalidate: _localScope,
  );

  /// Discards the hunks in [patch] from the working tree.
  Future<ActionResult> discardHunk(RepoLocation repo, String patch) =>
      _simple('Discard', _write.discardPatch(repo, patch));

  // ---- In-progress-op flow control ---------------------------------------
  // Abort/continue for merge/cherry-pick/revert/rebase. These end (or advance)
  // an in-progress op, so they refresh the repo state too — and, on continue,
  // the reads cache, since a continue creates a commit.

  /// `git merge --abort`.
  Future<ActionResult> mergeAbort(RepoLocation repo) =>
      _simple('Abort merge', _write.mergeAbort(repo), invalidate: _localScope);

  /// `git merge --continue`.
  Future<ActionResult> mergeContinue(RepoLocation repo) => _simple(
    'Continue merge',
    _write.mergeContinue(repo),
    invalidate: _localScope,
  );

  /// `git cherry-pick --abort`.
  Future<ActionResult> cherryPickAbort(RepoLocation repo) => _simple(
    'Abort cherry-pick',
    _write.cherryPickAbort(repo),
    invalidate: _localScope,
  );

  /// `git cherry-pick --continue`.
  Future<ActionResult> cherryPickContinue(RepoLocation repo) => _simple(
    'Continue cherry-pick',
    _write.cherryPickContinue(repo),
    invalidate: _localScope,
  );

  /// `git revert --abort`.
  Future<ActionResult> revertAbort(RepoLocation repo) => _simple(
    'Abort revert',
    _write.revertAbort(repo),
    invalidate: _localScope,
  );

  /// `git revert --continue`.
  Future<ActionResult> revertContinue(RepoLocation repo) => _simple(
    'Continue revert',
    _write.revertContinue(repo),
    invalidate: _localScope,
  );

  /// `git rebase --abort`.
  Future<ActionResult> rebaseAbort(RepoLocation repo) => _simple(
    'Abort rebase',
    _write.rebaseAbort(repo),
    invalidate: _localScope,
  );

  /// `git rebase --continue`.
  Future<ActionResult> rebaseContinue(RepoLocation repo) => _simple(
    'Continue rebase',
    _write.rebaseContinue(repo),
    invalidate: _localScope,
  );

  /// Maps a plain write result to an [ActionResult]: success invalidates
  /// [invalidate]; failure adds a '`label` failed: …' error message (so call
  /// sites can never silently swallow a git error).
  Future<ActionResult> _simple<T>(
    String label,
    Future<GitResult<T>> op, {
    Set<RepoDataScope> invalidate = const {RepoDataScope.reads},
  }) async {
    final result = await op;
    return switch (result) {
      GitSuccess() => ActionResult(
        ActionOutcome.success,
        invalidate: invalidate,
      ),
      GitFailure(:final message) => ActionResult(
        ActionOutcome.failed,
        invalidate: invalidate,
        message: '$label failed: $message',
        severity: MessageSeverity.error,
      ),
    };
  }

  /// Maps a conflict-bearing write result to an [ActionResult]: success,
  /// conflict (with a count message), or failure. [conflictPaths] returns the
  /// conflicted paths when the success-outcome is a conflict, else null.
  ActionResult _conflictable<T>(
    GitResult<T> result,
    String label,
    List<String>? Function(T outcome) conflictPaths,
  ) {
    switch (result) {
      case GitSuccess(:final value):
        final paths = conflictPaths(value);
        if (paths == null) {
          return const ActionResult(
            ActionOutcome.success,
            invalidate: _localScope,
          );
        }
        return ActionResult(
          ActionOutcome.conflict,
          invalidate: _localScope,
          message:
              '$label conflict in ${paths.length} file(s). '
              'Resolve in the conflicts panel below.',
          severity: MessageSeverity.error,
        );
      case GitFailure(:final message):
        return ActionResult(
          ActionOutcome.failed,
          invalidate: _localScope,
          message: '$label failed: $message',
          severity: MessageSeverity.error,
        );
    }
  }

  /// Drives a streaming git op through [progress], and on an auth-style failure
  /// prompts for an account and retries with the chosen credential. The user
  /// cancelling the prompt ends the loop; a non-auth failure ends it too.
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
    final resolved = profileResolved ? profile : await _resolveProfile(repo);
    StreamSubscription<GitProgress>? sub;
    final done = Completer<void>();
    var cancelled = false;
    // Register the cancel BEFORE listening so the operations UI can kill the
    // op: cancelling the subscription tears down the git process stream (whose
    // sync-writer finally kills the process), and we complete `done` so the
    // await below returns.
    final id = progress.start(
      kind,
      label,
      repo: repo,
      onCancel: () {
        cancelled = true;
        unawaited(sub?.cancel());
        if (!done.isCompleted) done.complete();
      },
    );
    sub = streamFactory(resolved?.spec).listen(
      (ev) => progress.progress(id, ev.fraction, ev.phase),
      onError: (Object e, StackTrace s) {
        if (!done.isCompleted) done.completeError(e, s);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    try {
      await done.future;
      if (cancelled) {
        progress.failure(id, 'Cancelled');
        return const ActionResult(ActionOutcome.failed);
      }
      progress.success(id);
      return const ActionResult.reads(ActionOutcome.success);
    } on Object catch (e) {
      // Classify ONLY git's stderr (via the injected extractor) — never the
      // full exception string, which embeds the argv and would false-positive.
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
      _log?.w('git $label failed: $e');
      progress.failure(id, e.toString());
      return const ActionResult(ActionOutcome.failed);
    }
  }
}
