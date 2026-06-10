import 'dart:io';

import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:gitopen/infrastructure/git/git_result_runner.dart';
import 'package:path/path.dart' as p;

/// The conflict-bearing sequencing commands (merge, rebase, cherry-pick,
/// revert) plus their abort/continue flow control and the merge preview.
/// These capture stdout+stderr (git reports CONFLICT on stdout) and map the
/// outcome to the typed `*Outcome` variants.  Moved verbatim from
/// `GitCliWriteOperations`.
final class GitCliSequencerWriter {
  GitCliSequencerWriter(this._git);
  final GitResultRunner _git;

  Future<GitResult<MergeOutcome>> merge(RepoLocation r, String ref,
      {MergeStrategy strategy = MergeStrategy.defaultStrategy}) async {
    final args = <String>['merge'];
    switch (strategy) {
      case MergeStrategy.defaultStrategy:
        break;
      case MergeStrategy.noFF:
        args.add('--no-ff');
      case MergeStrategy.squash:
        // `--squash` implies `--no-commit`; pair with `--ff` so git never
        // creates a merge commit, only updates the index.
        args.addAll(['--squash', '--ff']);
      case MergeStrategy.noCommit:
        args.addAll(['--no-ff', '--no-commit']);
    }
    args.add(ref);
    // Capture stdout+stderr so both can be inspected on failure.
    final result = await _git.capture(r.path, args);
    final out = result.stdout.toString();
    final err = result.stderr.toString();
    if (result.exitCode == 0) {
      if (out.contains('Already up to date')) {
        return const GitSuccess(MergeUpToDate());
      }
      // Squash and no-commit leave changes staged without creating a commit.
      if (strategy == MergeStrategy.squash ||
          strategy == MergeStrategy.noCommit) {
        return const GitSuccess(MergeStaged());
      }
      final ff = out.contains('Fast-forward');
      final head = await _git.head(r);
      if (ff) return GitSuccess(MergeFastForward(CommitSha(head)));
      return GitSuccess(MergeMerged(CommitSha(head)));
    }
    // Check for conflict in both stdout and stderr
    final combined = out + err;
    if (combined.contains('CONFLICT') ||
        combined.contains('Automatic merge failed')) {
      return GitSuccess(MergeConflict(await _git.listUnmergedPaths(r)));
    }
    final exc = GitProcessException(args, result.exitCode, err);
    return GitFailure(_git.classify(exc), err, err);
  }

  Future<GitResult<void>> mergeAbort(RepoLocation r) =>
      _git.runVoid(r, ['merge', '--abort']);

  Future<GitResult<CommitSha>> mergeContinue(RepoLocation r) =>
      _git.runThenHead(r, ['merge', '--continue', '--no-edit']);

  Future<GitResult<MergePreview>> previewMerge(
    RepoLocation r,
    String ref,
  ) async {
    // `git merge-tree --write-tree` is the modern (git 2.38+) dry-run form:
    // exits 0 on a clean merge, 1 on conflict, >1 on usage/error. With
    // `--name-only`, conflicted paths are printed after the tree OID and a
    // blank line.
    final head = await _git.head(r);
    final result = await _git.capture(
      r.path,
      [
        'merge-tree',
        '--write-tree',
        '--name-only',
        '--no-messages',
        head,
        ref,
      ],
    );
    if (result.exitCode == 0) return const GitSuccess(MergePreviewClean());
    if (result.exitCode == 1) {
      final lines = (result.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      // First line is the conflicted tree OID; the rest are paths.
      final paths = lines.length > 1 ? lines.sublist(1) : const <String>[];
      return GitSuccess(MergePreviewConflicts(paths));
    }
    final err = result.stderr.toString();
    final exc = GitProcessException(['merge-tree'], result.exitCode, err);
    return GitFailure(_git.classify(exc), err, err);
  }

  Future<GitResult<RebaseOutcome>> rebase(
    RepoLocation r,
    String upstream,
  ) async {
    final args = ['rebase', upstream];
    final result = await _git.capture(r.path, args);
    final out = result.stdout.toString();
    final err = result.stderr.toString();
    if (result.exitCode == 0) {
      if (out.contains('is up to date') || out.contains('up to date')) {
        return const GitSuccess(RebaseUpToDate());
      }
      final head = await _git.head(r);
      return GitSuccess(RebaseApplied(CommitSha(head)));
    }
    final combined = out + err;
    if (combined.contains('CONFLICT') ||
        combined.contains('could not apply') ||
        combined.contains('Resolve all conflicts')) {
      return GitSuccess(RebaseConflict(await _git.listUnmergedPaths(r)));
    }
    final exc = GitProcessException(args, result.exitCode, err);
    return GitFailure(_git.classify(exc), err, err);
  }

  Future<GitResult<RebaseOutcome>> interactiveRebase(
    RepoLocation r,
    CommitSha onto,
    List<RebaseTodoEntry> plan,
  ) {
    // Build the todo text — one line per entry, oldest-first, exactly as git
    // writes its own todo file. `drop` is emitted explicitly so the rebase is
    // self-documenting (omitting the line would also drop the commit).
    final todo = StringBuffer();
    for (final e in plan) {
      final verb = switch (e.action) {
        RebaseTodoAction.pick => 'pick',
        RebaseTodoAction.squash => 'squash',
        RebaseTodoAction.fixup => 'fixup',
        RebaseTodoAction.drop => 'drop',
      };
      todo.writeln('$verb ${e.sha.value}');
    }
    return _scriptedRebase(r, onto.value, todo.toString());
  }

  Future<GitResult<RebaseOutcome>> rewordCommit(
    RepoLocation r,
    CommitSha sha,
    String message,
  ) async {
    final List<String> later;
    try {
      // Commits after the target, oldest-first — they are replayed as picks.
      final raw = await _git.runner
          .run(r.path, ['rev-list', '--reverse', '${sha.value}..HEAD']);
      // Probing `sha^` up front gives a clean failure for the root commit
      // instead of a half-started rebase.
      await _git.runner.run(r.path, ['rev-parse', '--verify', '${sha.value}^']);
      later = raw.split('\n').where((l) => l.isNotEmpty).toList();
    } on GitProcessException catch (e) {
      return GitFailure(_git.classify(e), e.stderr, e.stderr);
    }
    final todo = StringBuffer()..writeln('reword ${sha.value}');
    for (final c in later) {
      todo.writeln('pick $c');
    }
    return _scriptedRebase(
      r,
      '${sha.value}^',
      todo.toString(),
      commitMessage: message,
    );
  }

  Future<GitResult<RebaseOutcome>> editAtCommit(
    RepoLocation r,
    CommitSha sha,
  ) async {
    final List<String> later;
    try {
      final raw = await _git.runner
          .run(r.path, ['rev-list', '--reverse', '${sha.value}..HEAD']);
      await _git.runner.run(r.path, ['rev-parse', '--verify', '${sha.value}^']);
      later = raw.split('\n').where((l) => l.isNotEmpty).toList();
    } on GitProcessException catch (e) {
      return GitFailure(_git.classify(e), e.stderr, e.stderr);
    }
    final todo = StringBuffer()..writeln('edit ${sha.value}');
    for (final c in later) {
      todo.writeln('pick $c');
    }
    return _scriptedRebase(r, '${sha.value}^', todo.toString());
  }

  /// Runs `git rebase -i <onto>` with a fully scripted todo list (no editor
  /// prompts). [commitMessage], when given, is fed to the single message
  /// prompt the todo raises (a `reword` line) via GIT_EDITOR.
  Future<GitResult<RebaseOutcome>> _scriptedRebase(
    RepoLocation r,
    String onto,
    String todoText, {
    String? commitMessage,
  }) async {
    // Write the scripted todo to a temp file. Git invokes
    //   sh -c "$GIT_SEQUENCE_EDITOR <git-todo-path>"
    // so we set GIT_SEQUENCE_EDITOR to a `cp` that overwrites git's todo file
    // with ours. Forward-slash paths keep Git-for-Windows' bundled `sh` happy.
    final tmpDir = Directory.systemTemp.createTempSync('gitopen-irebase-');
    final todoFile = File(p.join(tmpDir.path, 'todo'))
      ..writeAsStringSync(todoText);
    final todoPosix = todoFile.path.replaceAll(r'\', '/');

    // No-op editor for squash/fixup prompts; for a reword, the same trailing-
    // space `cp` trick overwrites COMMIT_EDITMSG with the prepared message.
    // (GIT_EDITOR wins over core.editor, so the override below only applies
    // when set.)
    var editor = 'true';
    if (commitMessage != null) {
      final msgFile = File(p.join(tmpDir.path, 'msg'))
        ..writeAsStringSync(
          commitMessage.endsWith('\n') ? commitMessage : '$commitMessage\n',
        );
      editor = "cp '${msgFile.path.replaceAll(r'\', '/')}' ";
    }

    final args = <String>[
      // `core.editor=true` is a no-op editor for any commit-message prompt
      // squash would otherwise raise (we keep messages as-is).
      '-c', 'core.editor=true',
      'rebase', '-i', onto,
    ];

    final env = buildGitEnvironment({
      // The trailing space lets git append the todo path as a second argument:
      //   cp "<ourtodo>" <git-todo-path>
      'GIT_SEQUENCE_EDITOR': "cp '$todoPosix' ",
      'GIT_EDITOR': editor,
    });

    try {
      final result = await _git.capture(r.path, args, environment: env);
      final out = result.stdout.toString();
      final err = result.stderr.toString();
      if (result.exitCode == 0) {
        // A todo with an `edit` line exits 0 while the rebase is still in
        // progress, stopped at that commit.
        if (Directory(p.join(r.path, '.git', 'rebase-merge')).existsSync() ||
            Directory(p.join(r.path, '.git', 'rebase-apply')).existsSync()) {
          return const GitSuccess(RebaseStoppedForEdit());
        }
        if (out.contains('is up to date') || out.contains('up to date')) {
          return const GitSuccess(RebaseUpToDate());
        }
        final head = await _git.head(r);
        return GitSuccess(RebaseApplied(CommitSha(head)));
      }
      final combined = out + err;
      if (combined.contains('CONFLICT') ||
          combined.contains('could not apply') ||
          combined.contains('Resolve all conflicts')) {
        return GitSuccess(RebaseConflict(await _git.listUnmergedPaths(r)));
      }
      final exc = GitProcessException(args, result.exitCode, err);
      return GitFailure(_git.classify(exc), err, err);
    } finally {
      try {
        tmpDir.deleteSync(recursive: true);
      } on Object {
        // Best-effort cleanup; ignore failures (e.g. locked files on Windows).
      }
    }
  }

  Future<GitResult<void>> rebaseAbort(RepoLocation r) =>
      _git.runVoid(r, ['rebase', '--abort']);

  Future<GitResult<CommitSha>> rebaseContinue(RepoLocation r) =>
      _git.runThenHead(r, ['-c', 'core.editor=true', 'rebase', '--continue']);

  Future<GitResult<void>> rebaseSkip(RepoLocation r) =>
      _git.runVoid(r, ['rebase', '--skip']);

  Future<GitResult<CherryPickOutcome>> cherryPick(
    RepoLocation r,
    CommitSha sha,
  ) async {
    // Capture stdout for conflict detection (git may write CONFLICT to
    // stdout).
    final result = await _git.capture(r.path, ['cherry-pick', sha.value]);
    final out = result.stdout.toString();
    final err = result.stderr.toString();
    if (result.exitCode == 0) {
      final head = await _git.head(r);
      return GitSuccess(CherryPickApplied(CommitSha(head)));
    }
    final combined = out + err;
    if (combined.contains('CONFLICT') ||
        combined.contains('after resolving the conflicts')) {
      return GitSuccess(CherryPickConflict(await _git.listUnmergedPaths(r)));
    }
    final exc = GitProcessException(
      ['cherry-pick', sha.value],
      result.exitCode,
      err,
    );
    return GitFailure(_git.classify(exc), err, err);
  }

  Future<GitResult<void>> cherryPickAbort(RepoLocation r) =>
      _git.runVoid(r, ['cherry-pick', '--abort']);

  Future<GitResult<CommitSha>> cherryPickContinue(RepoLocation r) =>
      _git.runThenHead(r, ['cherry-pick', '--continue']);

  Future<GitResult<RevertOutcome>> revert(
    RepoLocation r,
    CommitSha sha,
  ) async {
    final result =
        await _git.capture(r.path, ['revert', '--no-edit', sha.value]);
    final combined = '${result.stdout}\n${result.stderr}';
    if (result.exitCode == 0) {
      final head = await _git.head(r);
      return GitSuccess(RevertApplied(CommitSha(head)));
    }
    if (combined.contains('CONFLICT')) {
      final status = await _git.runner.run(
        r.path,
        ['diff', '--name-only', '--diff-filter=U'],
      );
      return GitSuccess(
        RevertConflict(
          status.split('\n').where((l) => l.isNotEmpty).toList(),
        ),
      );
    }
    return GitFailure(
      _git.classify(
        GitProcessException(
          ['revert'],
          result.exitCode,
          result.stderr.toString(),
        ),
      ),
      result.stderr.toString(),
      combined,
    );
  }

  Future<GitResult<void>> revertAbort(RepoLocation r) =>
      _git.runVoid(r, ['revert', '--abort']);

  Future<GitResult<CommitSha>> revertContinue(RepoLocation r) =>
      _git.runThenHead(r, ['revert', '--continue', '--no-edit']);
}
