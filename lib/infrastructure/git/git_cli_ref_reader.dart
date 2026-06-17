import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/refs/branch.dart';
import 'package:gitopen/domain/refs/reflog_entry.dart';
import 'package:gitopen/domain/refs/remote.dart';
import 'package:gitopen/domain/refs/stash.dart';
import 'package:gitopen/domain/refs/submodule.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/refs/worktree.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:gitopen/infrastructure/logging/app_logger.dart';

/// Reads refs and ref-like collections (branches, tags, remotes, stashes,
/// submodules) for the read-operations facade.  Moved verbatim from
/// `GitCliReadOperations`.
final class GitCliRefReader {
  GitCliRefReader(this._runner);
  final GitProcessRunner _runner;

  Future<List<Branch>> getLocalBranches(RepoLocation repo) {
    return _forEachRef(repo, scope: 'refs/heads');
  }

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
  /// from `git status --porcelain=v2 --branch` via `RepoStatus`.
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
      // `git remote -v` prints `name<TAB>url<SPACE>(fetch|push)` — a SPACE
      // before the direction, not a second tab. Split on the last space.
      final sep = rest.lastIndexOf(' ');
      if (sep < 0) continue;
      final url = rest.substring(0, sep);
      final qualifier = rest.substring(sep + 1).trim();
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

  Future<List<ReflogEntry>> getReflog(
    RepoLocation repo, {
    int limit = 100,
  }) async {
    final String stdout;
    try {
      stdout = await _runner.run(repo.path, [
        'reflog',
        '--format=%H%x00%gd%x00%gs',
        '-n',
        '$limit',
      ]);
    } on GitProcessException catch (e) {
      // An unborn HEAD (fresh `git init`) has no reflog yet.
      if (e.stderr.contains('does not have any commits yet') ||
          e.stderr.contains('unknown revision')) {
        return const [];
      }
      rethrow;
    }
    if (stdout.trim().isEmpty) return const [];

    final entries = <ReflogEntry>[];
    for (final line in stdout.split('\n')) {
      if (line.isEmpty) continue;
      final fields = _nulFields(line, 3);
      if (fields == null) continue;
      entries.add(ReflogEntry(
        sha: CommitSha(fields[0]),
        selector: fields[1],
        message: fields[2],
      ));
    }
    return entries;
  }

  Future<List<Worktree>> getWorktrees(RepoLocation repo) async {
    // Porcelain output is blank-line-separated records of
    //   worktree <path> / HEAD <sha> / branch refs/heads/x | detached | bare.
    final stdout =
        await _runner.run(repo.path, ['worktree', 'list', '--porcelain']);
    final trees = <Worktree>[];
    String? path;
    String? sha;
    String? branch;
    var bare = false;
    var detached = false;

    void flush() {
      if (path != null) {
        trees.add(Worktree(
          path: path!,
          branch: branch,
          headSha: sha != null ? CommitSha(sha!) : null,
          isBare: bare,
          isDetached: detached,
        ));
      }
      path = null;
      sha = null;
      branch = null;
      bare = false;
      detached = false;
    }

    for (final line in const LineSplitter().convert(stdout)) {
      if (line.isEmpty) {
        flush();
      } else if (line.startsWith('worktree ')) {
        path = line.substring('worktree '.length);
      } else if (line.startsWith('HEAD ')) {
        sha = line.substring('HEAD '.length);
      } else if (line.startsWith('branch refs/heads/')) {
        branch = line.substring('branch refs/heads/'.length);
      } else if (line == 'bare') {
        bare = true;
      } else if (line == 'detached') {
        detached = true;
      }
    }
    flush();
    return trees;
  }

  Future<List<Submodule>> getSubmodules(RepoLocation repo) async {
    // `git submodule status` exits 0 even with no submodules; empty output
    // means none are registered. Each line is:
    //   "<flag><40-hex> <path>[ (<describe>)]"
    // where <flag> is one of ' ', '-', '+', 'U'. The describe suffix is
    // present only for initialized submodules and is optional.
    final stdout = await _runner.run(repo.path, ['submodule', 'status']);
    if (stdout.trim().isEmpty) return [];

    // flag, sha, path, optional "(describe)".  The path can contain spaces, so
    // capture it lazily up to an optional trailing " (...)" group.
    final lineRe = RegExp(
      r'^([ \-+U])([0-9a-f]{40}) (.+?)(?: \((.*)\))?$',
    );

    final submodules = <Submodule>[];
    for (final line in const LineSplitter().convert(stdout)) {
      if (line.isEmpty) continue;
      final m = lineRe.firstMatch(line);
      if (m == null) continue;

      submodules.add(Submodule(
        path: m.group(3)!,
        sha: CommitSha(m.group(2)!),
        describe: m.group(4),
        status: _mapSubmoduleStatus(m.group(1)!),
      ));
    }
    return submodules;
  }

  SubmoduleStatus _mapSubmoduleStatus(String flag) {
    switch (flag) {
      case '-':
        return SubmoduleStatus.uninitialized;
      case '+':
        return SubmoduleStatus.modified;
      case 'U':
        return SubmoduleStatus.mergeConflict;
      case ' ':
      default:
        return SubmoduleStatus.upToDate;
    }
  }
}
