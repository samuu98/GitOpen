import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:gitopen/application/git/git_read_operations.dart';
import 'package:gitopen/domain/blame/blame_line.dart';
import 'package:gitopen/domain/commits/commit_info.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/commits/commit_signature.dart';
import 'package:gitopen/domain/diff/diff_hunk.dart';
import 'package:gitopen/domain/diff/diff_line.dart';
import 'package:gitopen/domain/diff/diff_result.dart';
import 'package:gitopen/domain/diff/diff_spec.dart';
import 'package:gitopen/domain/diff/file_diff.dart';
import 'package:gitopen/domain/files/file_tree_entry.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/refs/remote.dart';
import 'package:gitopen/domain/refs/stash.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:gitopen/infrastructure/logging/app_logger.dart';

final class GitCliReadOperations implements GitReadOperations {
  GitCliReadOperations({GitProcessRunner? runner})
      : _runner = runner ?? GitProcessRunner();
  final GitProcessRunner _runner;

  /// The 9 NUL-separated commit fields shared by [getCommits] and
  /// [getFileHistory].  Each record is exactly 9 fields, parsed by
  /// [_parseCommitFields]:
  /// sha, parents, author name/email/date, committer name/email/date, subject.
  /// The body (%b) is intentionally omitted — fetched on demand via
  /// [getCommitFullMessage].
  static const String _commitFormat =
      '%H%x00%P%x00%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI%x00%s';
  static const int _commitFieldCount = 9;

  @override
  Future<RepoStatus> getStatus(RepoLocation repo) async {
    final stdout = await _runner.run(repo.path, [
      'status', '--porcelain=v2', '--branch', '-z',
    ]);

    String? branch;
    CommitSha? headSha;
    var detached = false;
    var ahead = 0;
    var behind = 0;
    final entries = <WorkingFileEntry>[];

    // With -z, records are NUL-terminated. Split on NUL to get tokens.
    // Type-2 (rename/copy) entries consume two consecutive tokens: the entry
    // itself and then the original path.
    final tokens = stdout.split('\x00');
    // Drop a trailing empty token from the final NUL terminator.
    if (tokens.isNotEmpty && tokens.last.isEmpty) tokens.removeLast();

    var i = 0;
    while (i < tokens.length) {
      final tok = tokens[i];

      if (tok.startsWith('# branch.oid ')) {
        final value = tok.substring('# branch.oid '.length);
        if (value != '(initial)') headSha = CommitSha(value);
        i++;
        continue;
      }
      if (tok.startsWith('# branch.head ')) {
        final value = tok.substring('# branch.head '.length);
        if (value == '(detached)') {
          detached = true;
        } else {
          branch = value;
        }
        i++;
        continue;
      }
      if (tok.startsWith('# branch.ab ')) {
        // Format: "# branch.ab +<ahead> -<behind>"
        final value = tok.substring('# branch.ab '.length);
        final m = RegExp(r'\+(\d+)\s+-(\d+)').firstMatch(value);
        if (m != null) {
          ahead = int.tryParse(m.group(1)!) ?? 0;
          behind = int.tryParse(m.group(2)!) ?? 0;
        }
        i++;
        continue;
      }
      if (tok.startsWith('# ')) {
        i++;
        continue;
      }

      if (tok.startsWith('1 ')) {
        // 1 XY sub mH mI mW hH hI path  (space-separated; path is field 8)
        final parts = tok.split(' ');
        final xy = parts[1];
        final path = parts.sublist(8).join(' ');
        entries.add(WorkingFileEntry(
          path: path,
          indexState: _mapIndex(xy[0]),
          workingTreeState: _mapWorktree(xy[1]),
        ));
        i++;
        continue;
      }
      if (tok.startsWith('2 ')) {
        // 2 XY sub mH mI mW hH hI Xscore newPath
        // followed by origPath as the next NUL-separated token
        final parts = tok.split(' ');
        final xy = parts[1];
        final newPath = parts.sublist(9).join(' ');
        final origPath = i + 1 < tokens.length ? tokens[i + 1] : null;
        entries.add(WorkingFileEntry(
          path: newPath,
          indexState: _mapIndex(xy[0]),
          workingTreeState: _mapWorktree(xy[1]),
          oldPath: origPath,
        ));
        i += 2;
        continue;
      }
      if (tok.startsWith('u ')) {
        // unmerged: u XY sub m1 m2 m3 mW h1 h2 h3 path
        final parts = tok.split(' ');
        final xy = parts[1];
        final path = parts.sublist(10).join(' ');
        entries.add(WorkingFileEntry(
          path: path,
          indexState: _mapIndex(xy[0]),
          workingTreeState: WorkingFileState.conflicted,
        ));
        i++;
        continue;
      }
      if (tok.startsWith('? ')) {
        entries.add(WorkingFileEntry(
          path: tok.substring(2),
          indexState: WorkingFileState.unmodified,
          workingTreeState: WorkingFileState.untracked,
        ));
        i++;
        continue;
      }
      if (tok.startsWith('! ')) {
        entries.add(WorkingFileEntry(
          path: tok.substring(2),
          indexState: WorkingFileState.unmodified,
          workingTreeState: WorkingFileState.ignored,
        ));
        i++;
        continue;
      }
      // Unknown token: skip
      i++;
    }

    return RepoStatus(
      currentBranch: branch,
      headSha: headSha,
      isDetached: detached,
      isBare: false,
      entries: entries,
      ahead: ahead,
      behind: behind,
    );
  }

  WorkingFileState _mapIndex(String c) {
    switch (c) {
      case 'M':
      case 'T':
        return WorkingFileState.modified;
      case 'A':
        return WorkingFileState.added;
      case 'D':
        return WorkingFileState.deleted;
      case 'R':
      case 'C':
        return WorkingFileState.renamed;
      default:
        return WorkingFileState.unmodified;
    }
  }

  WorkingFileState _mapWorktree(String c) {
    switch (c) {
      case 'M':
      case 'T':
        return WorkingFileState.modified;
      case 'A':
        return WorkingFileState.added;
      case 'D':
        return WorkingFileState.deleted;
      case 'R':
      case 'C':
        return WorkingFileState.renamed;
      case 'U':
        return WorkingFileState.conflicted;
      case '?':
        return WorkingFileState.untracked;
      case '!':
        return WorkingFileState.ignored;
      default:
        return WorkingFileState.unmodified;
    }
  }

  @override
  Stream<CommitInfo> getCommits(RepoLocation repo, CommitQuery query) async* {
    // NOTE: format intentionally omits the commit body (%b).  For very large
    // repos the body dominates `git log` output (multi-paragraph merges,
    // generated changelogs, etc.) and was causing the graph load to blow up
    // memory.  The graph only ever displays the subject line; full message
    // is fetched on demand via [getCommitFullMessage] when a commit row is
    // selected.  Each commit produces exactly 9 NUL-separated fields.
    final args = <String>[
      'log', '-z',
      '--topo-order', '--date-order',
      '--format=$_commitFormat',
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

        while (pending.length >= _commitFieldCount) {
          final f = List<String>.generate(
              _commitFieldCount, (_) => pending.removeFirst());
          yield _parseCommitFields(f);
          emitted++;
          if (emitted % 500 == 0) {
            appLog.d('git[$tag] streamed $emitted commits '
                '(${sw.elapsedMilliseconds}ms)');
          }
        }
      }

      // Flush the trailing partial field (only non-empty if git didn't
      // terminate its last record with a NUL — defensive, shouldn't happen
      // with -z) and emit any final complete record.
      if (remainder.isNotEmpty) pending.add(remainder);
      while (pending.length >= _commitFieldCount) {
        final f = List<String>.generate(
            _commitFieldCount, (_) => pending.removeFirst());
        yield _parseCommitFields(f);
        emitted++;
      }

      final exit = await proc.exitCode;
      appLog.d('git[$tag] done in ${sw.elapsedMilliseconds}ms '
          '(exit=$exit, commits=$emitted)');
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
    );
  }

  @override
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

  @override
  Future<List<Branch>> getLocalBranches(RepoLocation repo) {
    return _forEachRef(repo, scope: 'refs/heads');
  }

  @override
  Future<List<Branch>> getRemoteBranches(RepoLocation repo) {
    // Remote refs can take a very long time on corporate monorepos that
    // never prune merged PR refs (tens of thousands of loose ref files
    // under .git/refs/remotes/ that Windows + AV scan slowly).  Cap with
    // a hard deadline so the UI never blocks waiting for this.
    return _forEachRef(
      repo,
      scope: 'refs/remotes',
      timeout: const Duration(seconds: 3),
    );
  }

  @override
  Future<List<Branch>> getBranches(RepoLocation repo) async {
    return [
      ...await getLocalBranches(repo),
      ...await getRemoteBranches(repo),
    ];
  }

  /// Streamed `for-each-ref` for one scope.
  ///
  /// Note: `upstream:track` is intentionally NOT included.  On repos with
  /// many local branches whose upstreams have a large divergence, that
  /// atom forces git to walk every commit between branch and upstream
  /// per-branch — `for-each-ref refs/heads` then turns from "fast" into
  /// "minutes".  Ahead/behind for the current branch is fetched cheaply
  /// from `git status --porcelain=v2 --branch` via [RepoStatus].
  ///
  /// When [timeout] is set, the underlying git process is killed if it
  /// hasn't completed by then.  Whatever rows we managed to parse so far
  /// are returned — partial data is better than no data, and not blocking
  /// the UI is the highest priority.
  Future<List<Branch>> _forEachRef(
    RepoLocation repo, {
    required String scope,
    Duration? timeout,
  }) async {
    const format =
        '%(refname)%00%(objectname)%00%(HEAD)%00%(upstream)%00';
    final args = ['for-each-ref', '--format=$format', scope];
    final sw = Stopwatch()..start();
    appLog.d('git[for-each-ref $scope] start (streaming)');

    final proc = await Process.start(
      _runner.executable,
      args,
      workingDirectory: repo.path,
    );

    final branches = <Branch>[];
    final stderrBuf = StringBuffer();
    unawaited(proc.stderr.transform(utf8.decoder).forEach(stderrBuf.write));

    // Race the stdout consumer against the timeout.  If git is wedged in
    // a kernel I/O wait (AV scanning a huge refs/ directory, slow network
    // FS, etc.), `proc.kill()` alone may not unblock the consumer — the
    // OS holds the handle until the syscall returns.  So instead of
    // relying on kill+exitCode, we fire-and-forget the kill and return
    // the partial list immediately when the deadline passes.
    final stdoutCompleter = Completer<void>();
    var timedOut = false;
    final sub = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) => _parseRefLine(line, branches, sw, scope),
      onDone: () {
        if (!stdoutCompleter.isCompleted) stdoutCompleter.complete();
      },
      onError: (Object e) {
        if (!stdoutCompleter.isCompleted) stdoutCompleter.complete();
      },
      cancelOnError: true,
    );

    Timer? timeoutTimer;
    if (timeout != null) {
      timeoutTimer = Timer(timeout, () {
        if (stdoutCompleter.isCompleted) return;
        timedOut = true;
        appLog.w('git[for-each-ref $scope] timeout after '
            '${timeout.inMilliseconds}ms — killing process; '
            'returning ${branches.length} partial result(s)');
        proc.kill(); // best-effort; may not unblock if stuck in kernel I/O
        unawaited(sub.cancel());
        stdoutCompleter.complete();
      });
    }

    await stdoutCompleter.future;
    timeoutTimer?.cancel();

    if (timedOut) {
      // Don't wait for exitCode — process may still be wedged.  The
      // partial branches list is what we have.
      appLog.d('git[for-each-ref $scope] returning ${branches.length} '
          'partial branches after timeout (${sw.elapsedMilliseconds}ms)');
      return branches;
    }

    final exit = await proc.exitCode;
    appLog.d('git[for-each-ref $scope] done in ${sw.elapsedMilliseconds}ms '
        '(exit=$exit, count=${branches.length})');
    if (exit != 0) {
      throw GitProcessException(args, exit, stderrBuf.toString());
    }
    return branches;
  }

  void _parseRefLine(
    String line,
    List<Branch> branches,
    Stopwatch sw,
    String scope,
  ) {
    if (line.isEmpty) return;
    final fields = _nulFields(line, 4);
    if (fields == null) return;

    final refname = fields[0];
    final sha = fields[1];
    final headMarker = fields[2];
    final upstream = fields[3];

    final String name;
    final bool isRemote;
    if (refname.startsWith('refs/heads/')) {
      name = refname.substring('refs/heads/'.length);
      isRemote = false;
    } else if (refname.startsWith('refs/remotes/')) {
      name = refname.substring('refs/remotes/'.length);
      isRemote = true;
    } else {
      return;
    }

    branches.add(Branch(
      name: name,
      fullName: refname,
      isRemote: isRemote,
      isCurrent: headMarker == '*',
      tipSha: sha.isNotEmpty ? CommitSha(sha) : null,
      upstreamFullName: upstream.isNotEmpty ? upstream : null,
      ahead: 0,
      behind: 0,
    ));

    // Periodic progress for very large ref sets so the log shows the
    // stream is alive rather than stuck.
    if (branches.length % 5000 == 0) {
      appLog.d('git[for-each-ref $scope] parsed ${branches.length} so far '
          '(${sw.elapsedMilliseconds}ms)');
    }
  }

  /// Splits a NUL-separated record into its fields, returning `null` when the
  /// line yields fewer than [min] fields.  Centralises the
  /// `split('\x00')` + length-guard pattern shared by the ref/tag/remote/stash
  /// parsers so each call site can index fields without repeating the guard.
  List<String>? _nulFields(String line, int min) {
    final fields = line.split('\x00');
    if (fields.length < min) return null;
    return fields;
  }

  @override
  Future<List<Tag>> getTags(RepoLocation repo) async {
    const format = '--format=%(refname:short)%00%(refname)%00'
        '%(*objectname)%00%(objectname)%00%(objecttype)';
    final args = [
      'for-each-ref',
      format,
      'refs/tags',
    ];
    final stdout = await _runner.run(repo.path, args);
    if (stdout.trim().isEmpty) return [];

    final lines = stdout.split('\n');
    final tags = <Tag>[];

    for (final line in lines) {
      if (line.isEmpty) continue;
      final fields = _nulFields(line, 5);
      if (fields == null) continue;

      final shortName = fields[0];
      final fullName = fields[1];
      final peeledSha = fields[2]; // non-empty for annotated tags
      final objectSha = fields[3];
      final objectType = fields[4];

      final targetSha = peeledSha.isNotEmpty ? peeledSha : objectSha;
      if (targetSha.isEmpty) continue;

      tags.add(Tag(
        name: shortName,
        fullName: fullName,
        targetSha: CommitSha(targetSha),
        isAnnotated: objectType == 'tag',
      ));
    }

    return tags;
  }

  @override
  Future<List<Remote>> getRemotes(RepoLocation repo) async {
    // Step 1: parse remote names and urls from `git remote -v`
    final remoteVOutput = await _runner.run(repo.path, ['remote', '-v']);
    if (remoteVOutput.trim().isEmpty) return [];

    // Map from remote name to url (deduped; fetch entry preferred)
    final remoteUrls = <String, String>{};
    for (final line in remoteVOutput.split('\n')) {
      if (line.isEmpty) continue;
      // Format: "name\turl\t(fetch)" or "name\turl\t(push)"
      final tab = line.indexOf('\t');
      if (tab < 0) continue;
      final name = line.substring(0, tab);
      final rest = line.substring(tab + 1);
      final tab2 = rest.lastIndexOf('\t');
      if (tab2 < 0) continue;
      final url = rest.substring(0, tab2);
      final qualifier = rest.substring(tab2 + 1);
      if (qualifier == '(fetch)' || !remoteUrls.containsKey(name)) {
        remoteUrls[name] = url;
      }
    }

    if (remoteUrls.isEmpty) return [];

    // Step 2: get remote branches grouped by remote name
    const branchFormat = '--format=%(refname)%00%(objectname)%00%(HEAD)%00'
        '%(upstream)%00%(upstream:track)';
    final branchArgs = [
      'for-each-ref',
      branchFormat,
      'refs/remotes',
    ];
    final branchOut = await _runner.run(repo.path, branchArgs);
    final remoteBranches = <String, List<Branch>>{};
    for (final name in remoteUrls.keys) {
      remoteBranches[name] = [];
    }

    if (branchOut.trim().isNotEmpty) {
      final aheadBehindRe = RegExp(r'(?:ahead (\d+))?(?:.*?behind (\d+))?');
      for (final line in branchOut.split('\n')) {
        if (line.isEmpty) continue;
        final fields = _nulFields(line, 5);
        if (fields == null) continue;

        final refname = fields[0];
        final sha = fields[1];
        final headMarker = fields[2];
        final upstream = fields[3];
        final track = fields[4];

        if (!refname.startsWith('refs/remotes/')) continue;
        final withoutPrefix = refname.substring('refs/remotes/'.length);

        // Determine which remote this belongs to
        String? remoteName;
        for (final rn in remoteUrls.keys) {
          if (withoutPrefix.startsWith('$rn/')) {
            remoteName = rn;
            break;
          }
        }
        if (remoteName == null) continue;

        // Skip the HEAD symbolic ref (e.g., refs/remotes/origin/HEAD)
        if (withoutPrefix.endsWith('/HEAD')) continue;

        var ahead = 0;
        var behind = 0;
        if (track.isNotEmpty) {
          final m = aheadBehindRe.firstMatch(track);
          if (m != null) {
            ahead = int.tryParse(m.group(1) ?? '') ?? 0;
            behind = int.tryParse(m.group(2) ?? '') ?? 0;
          }
        }

        remoteBranches[remoteName]!.add(Branch(
          name: withoutPrefix,
          fullName: refname,
          isRemote: true,
          isCurrent: headMarker == '*',
          tipSha: sha.isNotEmpty ? CommitSha(sha) : null,
          upstreamFullName: upstream.isNotEmpty ? upstream : null,
          ahead: ahead,
          behind: behind,
        ));
      }
    }

    return remoteUrls.entries
        .map((e) => Remote(
              name: e.key,
              url: e.value,
              branches: remoteBranches[e.key] ?? [],
            ))
        .toList();
  }

  @override
  Future<List<Stash>> getStashes(RepoLocation repo) async {
    // git stash list exits 0 even with an empty stash; empty output means no
    // stashes.
    final stdout = await _runner.run(
        repo.path, ['stash', 'list', '--format=%H%x00%gd%x00%gs%x00%ai']);
    if (stdout.trim().isEmpty) return [];

    final stashes = <Stash>[];
    final indexRe = RegExp(r'stash@\{(\d+)\}');

    for (final line in stdout.split('\n')) {
      if (line.isEmpty) continue;
      final fields = _nulFields(line, 4);
      if (fields == null) continue;

      final sha = fields[0];
      final reflogSelector = fields[1]; // e.g., stash@{0}
      final message = fields[2];
      final dateStr = fields[3];

      final indexMatch = indexRe.firstMatch(reflogSelector);
      final index = indexMatch != null ? int.parse(indexMatch.group(1)!) : 0;

      DateTime createdAt;
      try {
        createdAt = DateTime.parse(dateStr);
      } on Object catch (_) {
        createdAt = DateTime.fromMillisecondsSinceEpoch(0);
      }

      stashes.add(Stash(
        index: index,
        sha: CommitSha(sha),
        message: message,
        createdAt: createdAt,
      ));
    }

    return stashes;
  }

  @override
  Future<DiffResult> getDiff(RepoLocation repo, DiffSpec spec) async {
    final args = switch (spec) {
      DiffSpecCommitVsParent(:final commitSha) => [
          // `--first-parent -m` makes merge commits emit a normal 2-way diff
          // against their first parent (Fork/GitKraken default) instead of a
          // combined diff (diff --cc / @@@) the unified parser can't read.
          // It is a no-op on normal and root commits, so it is safe for all
          // single-commit diffs.
          'show', commitSha.value, '--first-parent', '-m',
          '--format=', '--raw', '-p', '--no-color',
        ],
      DiffSpecCommitVsCommit(:final from, :final to) => [
          'diff', '${from.value}..${to.value}', '--raw', '-p', '--no-color',
        ],
      DiffSpecIndexVsHead() => [
          'diff', '--cached', '--raw', '-p', '--no-color',
        ],
      DiffSpecWorkingTreeVsIndex() => [
          'diff', '--raw', '-p', '--no-color',
        ],
    };
    final stdout = await _runner.run(repo.path, args);
    return _DiffParser(stdout).parse();
  }

  @override
  Future<List<FileTreeEntry>> getFileTree(
      RepoLocation repo, CommitSha sha, String path) async {
    final ref = path.isEmpty ? sha.value : '${sha.value}:$path';
    final stdout = await _runner.run(repo.path, ['ls-tree', '-l', ref]);
    final entries = <FileTreeEntry>[];
    for (final line in stdout.split('\n')) {
      if (line.isEmpty) continue;
      final tabIdx = line.indexOf('\t');
      if (tabIdx < 0) continue;
      final meta = line.substring(0, tabIdx).split(RegExp(r'\s+'));
      if (meta.length < 4) continue;
      final mode = meta[0];
      final type = meta[1];
      // meta[2] is object sha (not needed here)
      final sizeStr = meta[3];
      final filePath = line.substring(tabIdx + 1);
      final name = filePath.contains('/')
          ? filePath.substring(filePath.lastIndexOf('/') + 1)
          : filePath;
      final kind = _mapTreeKind(type, mode);
      final size = sizeStr == '-' ? null : int.tryParse(sizeStr);
      entries.add(FileTreeEntry(
        name: name,
        fullPath: path.isEmpty ? filePath : '$path/$filePath',
        kind: kind,
        sizeBytes: size,
        containingCommit: sha,
      ));
    }
    return entries;
  }

  @override
  Future<List<CommitInfo>> getFileHistory(
    RepoLocation repo,
    String path, {
    int? take,
  }) async {
    // --follow tracks the file across renames; -z + the shared 9-field
    // format means each commit produces exactly [_commitFieldCount]
    // NUL-separated fields, parsed identically to [getCommits].  `--` keeps
    // git from treating the path as a revision.
    final args = <String>[
      'log',
      '--follow',
      '-z',
      '--format=$_commitFormat',
    ];
    if (take != null) args.add('--max-count=$take');
    args
      ..add('--')
      ..add(path);

    final stdout = await _runner.run(repo.path, args);
    return _parseCommitRecords(stdout);
  }

  /// Splits the buffered NUL-separated output of a
  /// `log --format=$_commitFormat` invocation into [CommitInfo]s.  Shared by
  /// [getFileHistory]; mirrors the
  /// field-chunking the streaming [getCommits] does, so a record is exactly
  /// [_commitFieldCount] fields.  A trailing empty token (from the final NUL
  /// terminator) is dropped before chunking.
  List<CommitInfo> _parseCommitRecords(String stdout) {
    if (stdout.isEmpty) return const [];
    final tokens = stdout.split('\x00');
    if (tokens.isNotEmpty && tokens.last.isEmpty) tokens.removeLast();

    final commits = <CommitInfo>[];
    var i = 0;
    while (i + _commitFieldCount <= tokens.length) {
      commits.add(
        _parseCommitFields(tokens.sublist(i, i + _commitFieldCount)),
      );
      i += _commitFieldCount;
    }
    return commits;
  }

  @override
  Future<List<BlameLine>> getBlame(
    RepoLocation repo,
    String path, {
    CommitSha? at,
  }) async {
    final args = <String>['blame', '--porcelain'];
    if (at != null) args.add(at.value);
    args
      ..add('--')
      ..add(path);

    final stdout = await _runner.run(repo.path, args);
    return _BlameParser(stdout).parse();
  }

  FileTreeKind _mapTreeKind(String type, String mode) {
    if (type == 'tree') return FileTreeKind.tree;
    if (type == 'commit') return FileTreeKind.submodule;
    if (mode == '120000') return FileTreeKind.symlink;
    return FileTreeKind.blob;
  }
}

/// Stateful parser for git's combined `--raw -p` (unified) diff output.
///
/// Extracted verbatim from [GitCliReadOperations.getDiff] so that the diff
/// command construction stays in the read-operations facade while the line-by
/// -line parsing — which is the bulk of the logic — lives in one focused
/// place.  Behaviour is identical: same field indices, regexes, and guards.
class _DiffParser {
  _DiffParser(this._stdout);

  final String _stdout;

  final List<FileDiff> _files = <FileDiff>[];
  final Map<String, _RawEntry> _rawByPath = <String, _RawEntry>{};

  DiffResult parse() {
    final lines = _stdout.split('\n');
    var i = 0;

    // Skip blank lines at start (--format= produces an empty header line)
    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }

    // Parse raw status block (lines starting with ':')
    while (i < lines.length && lines[i].startsWith(':')) {
      final line = lines[i].trimRight();
      final tabIdx = line.indexOf('\t');
      if (tabIdx >= 0) {
        final meta = line.substring(0, tabIdx).split(' ');
        if (meta.length >= 5) {
          final status = meta[4]; // 'A', 'M', 'R100', etc.
          final letter = status[0];
          final parts = line.split('\t');
          String path;
          String? oldPath;
          if ((letter == 'R' || letter == 'C') && parts.length >= 3) {
            oldPath = parts[1];
            path = parts[2];
          } else {
            path = parts[1];
          }
          _rawByPath[path] = _RawEntry(letter, oldPath);
        }
      }
      i++;
    }

    // Parse unified diff blocks
    while (i < lines.length) {
      if (!lines[i].startsWith('diff --git ')) {
        i++;
        continue;
      }

      // Extract new path from "diff --git a/<path> b/<path>"
      final pathMatch =
          RegExp(r'^diff --git a/(.+) b/(.+)$').firstMatch(lines[i]);
      if (pathMatch == null) {
        i++;
        continue;
      }
      final newPath = pathMatch.group(2)!;
      final raw = _rawByPath[newPath];
      final changeKind = _mapDiffStatus(raw?.status ?? 'M');
      var isBinary = false;
      final hunks = <DiffHunk>[];
      var added = 0;
      var deleted = 0;
      i++;

      // Skip header lines until first @@ or next diff --git
      while (i < lines.length &&
          !lines[i].startsWith('@@') &&
          !lines[i].startsWith('diff --git ')) {
        if (lines[i].contains('Binary files')) {
          isBinary = true;
        }
        i++;
      }

      DiffHunk? currentHunk;
      var hunkLines = <DiffLine>[];
      var oldLine = 0;
      var newLine = 0;

      while (
          i < lines.length && !lines[i].startsWith('diff --git ')) {
        final line = lines[i];
        if (line.startsWith('@@')) {
          // Flush previous hunk
          if (currentHunk != null) {
            hunks.add(DiffHunk(
              oldStart: currentHunk.oldStart,
              oldCount: currentHunk.oldCount,
              newStart: currentHunk.newStart,
              newCount: currentHunk.newCount,
              header: currentHunk.header,
              lines: hunkLines,
            ));
            hunkLines = [];
          }
          final m = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')
              .firstMatch(line);
          if (m == null) {
            i++;
            continue;
          }
          final oldStart = int.parse(m.group(1)!);
          final oldCount =
              m.group(2) != null ? int.parse(m.group(2)!) : 1;
          final newStart = int.parse(m.group(3)!);
          final newCount =
              m.group(4) != null ? int.parse(m.group(4)!) : 1;
          oldLine = oldStart;
          newLine = newStart;
          currentHunk = DiffHunk(
            oldStart: oldStart,
            oldCount: oldCount,
            newStart: newStart,
            newCount: newCount,
            header: line,
            lines: const [],
          );
          i++;
          continue;
        }

        if (currentHunk == null) {
          i++;
          continue;
        }
        if (line.isEmpty) {
          i++;
          continue;
        }

        switch (line[0]) {
          case '+':
            if (line.startsWith('+++')) {
              i++;
              continue;
            }
            hunkLines.add(DiffLine(
                kind: DiffLineKind.addition,
                newLine: newLine++,
                content: line.substring(1)));
            added++;
          case '-':
            if (line.startsWith('---')) {
              i++;
              continue;
            }
            hunkLines.add(DiffLine(
                kind: DiffLineKind.deletion,
                oldLine: oldLine++,
                content: line.substring(1)));
            deleted++;
          case ' ':
            hunkLines.add(DiffLine(
                kind: DiffLineKind.context,
                oldLine: oldLine++,
                newLine: newLine++,
                content: line.substring(1)));
          case r'\':
            // "\ No newline at end of file" — ignore
            break;
          default:
            break;
        }
        i++;
      }

      if (currentHunk != null) {
        hunks.add(DiffHunk(
          oldStart: currentHunk.oldStart,
          oldCount: currentHunk.oldCount,
          newStart: currentHunk.newStart,
          newCount: currentHunk.newCount,
          header: currentHunk.header,
          lines: hunkLines,
        ));
      }

      _files.add(FileDiff(
        path: newPath,
        oldPath: raw?.oldPath,
        changeKind: changeKind,
        isBinary: isBinary,
        linesAdded: added,
        linesDeleted: deleted,
        hunks: hunks,
      ));
    }

    return DiffResult(files: _files);
  }

  FileChangeKind _mapDiffStatus(String letter) {
    switch (letter) {
      case 'A':
        return FileChangeKind.added;
      case 'D':
        return FileChangeKind.deleted;
      case 'M':
        return FileChangeKind.modified;
      case 'R':
        return FileChangeKind.renamed;
      case 'C':
        return FileChangeKind.copied;
      case 'T':
        return FileChangeKind.typeChanged;
      case 'U':
        return FileChangeKind.unmerged;
      default:
        return FileChangeKind.modified;
    }
  }
}

class _RawEntry {
  _RawEntry(this.status, this.oldPath);
  final String status;
  final String? oldPath;
}

/// Parser for `git blame --porcelain` output.
///
/// Porcelain groups one or more consecutive final-file lines per record.
/// Each record begins with a header line:
///   `<40-hex-sha> <orig-line> <final-line> [<lines-in-this-group>]`
/// followed by zero or more extended headers (`author `, `author-mail `,
/// `author-time `, `summary `, …) and finally the literal content line, which
/// is the only line that starts with a TAB.
///
/// The author/time headers are emitted in full only the FIRST time a commit
/// is seen; later groups for the same commit carry just the header line.  So
/// we cache author name + time per sha and reuse them for repeat appearances.
class _BlameParser {
  _BlameParser(this._stdout);

  final String _stdout;

  final Map<String, ({String name, DateTime time})> _meta = {};

  List<BlameLine> parse() {
    final lines = const LineSplitter().convert(_stdout);
    final result = <BlameLine>[];

    String? currentSha;
    var currentFinalLine = 0;
    String? pendingName;
    int? pendingTimeSecs;

    for (final line in lines) {
      if (line.startsWith('\t')) {
        // Content line — closes the current record's first (or only) line.
        final sha = currentSha;
        if (sha == null) continue;

        if (pendingName != null && pendingTimeSecs != null) {
          _meta[sha] = (
            name: pendingName,
            time: DateTime.fromMillisecondsSinceEpoch(
              pendingTimeSecs * 1000,
              isUtc: true,
            ),
          );
        }
        final meta = _meta[sha];

        result.add(BlameLine(
          lineNumber: currentFinalLine,
          content: line.substring(1),
          sha: CommitSha(sha),
          authorName: meta?.name ?? '',
          authorTime: meta?.time ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ));

        pendingName = null;
        pendingTimeSecs = null;
        continue;
      }

      if (line.startsWith('author ')) {
        pendingName = line.substring('author '.length);
        continue;
      }
      if (line.startsWith('author-time ')) {
        pendingTimeSecs =
            int.tryParse(line.substring('author-time '.length).trim());
        continue;
      }

      // Header line: "<sha> <orig> <final> [count]".  A 40-hex prefix followed
      // by a space and a digit distinguishes it from extended headers like
      // "summary ..." or "filename ...".
      final m = RegExp(r'^([0-9a-f]{40}) \d+ (\d+)(?: \d+)?$').firstMatch(line);
      if (m != null) {
        currentSha = m.group(1);
        currentFinalLine = int.parse(m.group(2)!);
      }
    }

    return result;
  }
}
