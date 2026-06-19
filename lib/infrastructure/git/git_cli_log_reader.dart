import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/commits/commit_signature.dart';
import 'package:gitopen/domain/commits/gpg_signature_status.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:gitopen/infrastructure/logging/app_logger.dart';

/// The base NUL-separated `git log` fields shared by [GitCliLogReader]'s
/// commit readers, in order: sha, parents, author name/email/date, committer
/// name/email/date, subject. The body (%b) is intentionally omitted — for big
/// repos it dominates the log output and is fetched on demand instead (see
/// [GitCliLogReader.getCommitFullMessage]).
const String _baseCommitFormat =
    '%H%x00%P%x00%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI%x00%s';
const int _baseCommitFieldCount = 9;

/// Builds the `git log --format` string for one commit record.
///
/// When [verifySignature] is true, `%G?` (GPG status) is appended as a final
/// field. `%G?` makes git **verify** every commit's signature, which costs
/// seconds on a history with signed commits whose public keys are not present
/// locally — so callers that never display the status (the commit graph,
/// file history) leave it off and the log returns promptly.
String commitLogFormat({required bool verifySignature}) =>
    verifySignature ? '$_baseCommitFormat%x00%G?' : _baseCommitFormat;

/// The number of NUL-separated fields [commitLogFormat] emits per commit.
int commitLogFieldCount({required bool verifySignature}) =>
    verifySignature ? _baseCommitFieldCount + 1 : _baseCommitFieldCount;

/// Reads commit history (`git log`) for the read-operations facade: the
/// streaming graph log, per-file history, and on-demand full messages.
/// Moved verbatim from `GitCliReadOperations`.
final class GitCliLogReader {
  GitCliLogReader(this._runner);
  final GitProcessRunner _runner;

  Stream<CommitInfo> getCommits(RepoLocation repo, CommitQuery query) async* {
    // NOTE: format intentionally omits the commit body (%b).  For very large
    // repos the body dominates `git log` output (multi-paragraph merges,
    // generated changelogs, etc.) and was causing the graph load to blow up
    // memory.  The graph only ever displays the subject line; full message
    // is fetched on demand via [getCommitFullMessage] when a commit row is
    // selected.  GPG status (%G?) is included only when the caller asks
    // ([CommitQuery.verifySignature]) because verifying every commit is
    // multi-second on signed histories; each commit produces exactly
    // [fieldCount] NUL-separated fields.
    final fieldCount = commitLogFieldCount(
      verifySignature: query.verifySignature,
    );
    final args = <String>[
      'log',
      '-z',
      '--topo-order',
      '--date-order',
      '--format=${commitLogFormat(verifySignature: query.verifySignature)}',
    ];
    if (query.skip != null) args.add('--skip=${query.skip}');
    if (query.take != null) args.add('--max-count=${query.take}');

    // Search filters.  Appended only when set so that an empty query produces
    // byte-identical args to the pre-search behaviour.  When BOTH grep and
    // author are present, --all-match makes git require every --grep/--author
    // condition to hold (git's default is to OR them).
    final grep = query.grep;
    if (grep != null) {
      args
        ..add('--grep=$grep')
        ..add('--regexp-ignore-case');
    }
    final author = query.author;
    if (author != null) {
      args.add('--author=$author');
    }
    if (grep != null && author != null) {
      args.add('--all-match');
    }
    final touchingContent = query.touchingContent;
    if (touchingContent != null) {
      args.add('-S$touchingContent');
    }

    if (query.refs != null && query.refs!.isNotEmpty) {
      args.addAll(query.refs!);
    } else if (query.refSpec != null) {
      args.add(query.refSpec!);
    } else {
      // Without explicit refs, include all commits reachable from any ref so
      // that commits only referenced by tags (not by a branch HEAD) still
      // appear in the graph and their tag decorations show correctly.
      args.add('--all');
    }

    // Stream the output instead of buffering the whole stdout via
    // [Process.run].  On big repos this avoids holding the full log
    // payload in memory, and — more importantly for debugging — emits
    // periodic progress log lines so a hang shows up at a specific
    // commit count instead of as silent dead air.  If the caller cancels
    // or throws while iterating, the [try/finally] makes sure the spawned
    // git process is killed so we don't leak a wedged subprocess.
    const tag = 'log -z --topo-order';
    final sw = Stopwatch()..start();
    appLog.d('git[$tag] start (streaming)');

    final proc = await Process.start(
      _runner.executable,
      args,
      workingDirectory: repo.path,
    );
    final stderrBuf = StringBuffer();
    unawaited(proc.stderr.transform(utf8.decoder).forEach(stderrBuf.write));

    final pending = Queue<String>();
    var remainder = '';
    var emitted = 0;
    var completedNormally = false;

    try {
      await for (final chunk in proc.stdout.transform(utf8.decoder)) {
        final combined = remainder + chunk;
        final parts = combined.split('\x00');
        // Last part is the unterminated tail (or empty if the chunk ended
        // exactly on a NUL).  Everything before it is a complete field.
        remainder = parts.removeLast();
        pending.addAll(parts);

        while (pending.length >= fieldCount) {
          final f = List<String>.generate(
            fieldCount,
            (_) => pending.removeFirst(),
          );
          yield _parseCommitFields(f);
          emitted++;
          if (emitted % 500 == 0) {
            appLog.d(
              'git[$tag] streamed $emitted commits '
              '(${sw.elapsedMilliseconds}ms)',
            );
          }
        }
      }

      // Flush the trailing partial field (only non-empty if git didn't
      // terminate its last record with a NUL — defensive, shouldn't happen
      // with -z) and emit any final complete record.
      if (remainder.isNotEmpty) pending.add(remainder);
      while (pending.length >= fieldCount) {
        final f = List<String>.generate(
          fieldCount,
          (_) => pending.removeFirst(),
        );
        yield _parseCommitFields(f);
        emitted++;
      }

      final exit = await proc.exitCode;
      appLog.d(
        'git[$tag] done in ${sw.elapsedMilliseconds}ms '
        '(exit=$exit, commits=$emitted)',
      );
      completedNormally = true;

      if (exit != 0) {
        final err = stderrBuf.toString();
        // Empty repo: 'fatal: your current branch ... does not have any
        // commits yet' or 'unknown revision'. Treat both as empty.
        if (err.contains('does not have any commits yet') ||
            err.contains('bad default revision') ||
            err.contains('unknown revision')) {
          return;
        }
        throw GitProcessException(args, exit, err);
      }
    } finally {
      if (!completedNormally) {
        // Caller bailed out (timeout, cancel, error) — terminate the
        // subprocess so we don't leak a wedged git.exe.
        proc.kill();
      }
    }
  }

  CommitInfo _parseCommitFields(List<String> f) {
    final summary = f[8];
    return CommitInfo(
      sha: CommitSha(f[0]),
      parentShas: f[1].isEmpty
          ? const []
          : f[1].split(' ').map(CommitSha.new).toList(),
      author: CommitSignature(f[2], f[3], DateTime.parse(f[4])),
      committer: CommitSignature(f[5], f[6], DateTime.parse(f[7])),
      summary: summary,
      message: summary, // body fetched on demand via getCommitFullMessage
      // The %G? field is present only when signature verification was
      // requested (see [commitLogFormat]); absent → treat as unsigned.
      signatureStatus: f.length > _baseCommitFieldCount
          ? GpgSignatureStatus.fromGitCode(f[9])
          : GpgSignatureStatus.unsigned,
    );
  }

  Future<String?> getCommitFullMessage(
    RepoLocation repo,
    CommitSha sha,
  ) async {
    try {
      final out = await _runner.run(
        repo.path,
        ['log', '-1', '--format=%B', sha.value],
      );
      return out.trimRight();
    } on GitProcessException {
      return null;
    }
  }

  /// Symmetric divergence counts between two commits:
  /// `git rev-list --left-right --count a...b` → (left: only reachable from
  /// [a], right: only reachable from [b]).
  Future<({int left, int right})> countDivergence(
    RepoLocation repo,
    CommitSha a,
    CommitSha b,
  ) async {
    final out = await _runner.run(repo.path, [
      'rev-list',
      '--left-right',
      '--count',
      '${a.value}...${b.value}',
    ]);
    final parts = out.trim().split(RegExp(r'\s+'));
    return (left: int.parse(parts[0]), right: int.parse(parts[1]));
  }

  Future<List<CommitInfo>> getFileHistory(
    RepoLocation repo,
    String path, {
    int? take,
  }) async {
    // --follow tracks the file across renames; -z + the shared base format
    // means each commit produces exactly [_baseCommitFieldCount] NUL-separated
    // fields, parsed identically to [getCommits].  `--` keeps git from
    // treating the path as a revision. The file-history list does not show
    // signature status, so verification (%G?) is omitted.
    final args = <String>[
      'log',
      '--follow',
      '-z',
      '--format=${commitLogFormat(verifySignature: false)}',
    ];
    if (take != null) args.add('--max-count=$take');
    args
      ..add('--')
      ..add(path);

    final stdout = await _runner.run(repo.path, args);
    return _parseCommitRecords(
      stdout,
      commitLogFieldCount(verifySignature: false),
    );
  }

  /// Splits the buffered NUL-separated output of a `log --format` invocation
  /// into [CommitInfo]s.  Shared by [getFileHistory]; mirrors the
  /// field-chunking the streaming [getCommits] does, so a record is exactly
  /// [fieldCount] fields.  A trailing empty token (from the final NUL
  /// terminator) is dropped before chunking.
  List<CommitInfo> _parseCommitRecords(String stdout, int fieldCount) {
    if (stdout.isEmpty) return const [];
    final tokens = stdout.split('\x00');
    if (tokens.isNotEmpty && tokens.last.isEmpty) tokens.removeLast();

    final commits = <CommitInfo>[];
    var i = 0;
    while (i + fieldCount <= tokens.length) {
      commits.add(
        _parseCommitFields(tokens.sublist(i, i + fieldCount)),
      );
      i += fieldCount;
    }
    return commits;
  }
}
