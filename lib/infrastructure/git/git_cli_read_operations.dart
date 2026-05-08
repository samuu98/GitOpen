import '../../application/git/git_read_operations.dart';
import '../../domain/commits/commit_info.dart';
import '../../domain/commits/commit_sha.dart';
import '../../domain/commits/commit_signature.dart';
import '../../domain/diff/diff_result.dart';
import '../../domain/diff/diff_spec.dart';
import '../../domain/files/file_tree_entry.dart';
import '../../domain/refs/branch.dart';
import '../../domain/refs/remote.dart';
import '../../domain/refs/stash.dart';
import '../../domain/refs/tag.dart';
import '../../domain/repositories/repo_location.dart';
import '../../domain/status/repo_status.dart';
import '../../domain/status/working_file_entry.dart';
import 'git_process_runner.dart';

final class GitCliReadOperations implements GitReadOperations {
  final GitProcessRunner _runner;
  GitCliReadOperations({GitProcessRunner? runner})
      : _runner = runner ?? GitProcessRunner();

  @override
  Future<RepoStatus> getStatus(RepoLocation repo) async {
    final stdout = await _runner.run(repo.path, [
      'status', '--porcelain=v2', '--branch', '-z',
    ]);

    String? branch;
    CommitSha? headSha;
    bool detached = false;
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
    final args = <String>[
      'log', '-z',
      '--topo-order', '--date-order',
      '--format=%H%x00%P%x00%an%x00%ae%x00%aI%x00%cn%x00%ce%x00%cI%x00%s%x00%b',
    ];
    if (query.skip != null) args.add('--skip=${query.skip}');
    if (query.take != null) args.add('--max-count=${query.take}');
    if (query.refSpec != null) args.add(query.refSpec!);

    String stdout;
    try {
      stdout = await _runner.run(repo.path, args);
    } on GitProcessException catch (e) {
      // Empty repo: 'fatal: your current branch ... does not have any commits yet'
      // or 'unknown revision'. Treat both as empty.
      if (e.stderr.contains('does not have any commits yet') ||
          e.stderr.contains('bad default revision') ||
          e.stderr.contains('unknown revision')) {
        return;
      }
      rethrow;
    }

    // Each commit produces exactly 10 NUL-separated fields. The -z flag adds
    // one extra NUL terminator after each commit record, which in practice
    // means a single trailing empty string after the last commit's body.
    // Strip only that single trailing empty to avoid eating an empty body field.
    final fields = stdout.split('\x00');
    if (fields.isNotEmpty && fields.last.isEmpty) {
      fields.removeLast();
    }
    for (var i = 0; i + 9 < fields.length; i += 10) {
      yield CommitInfo(
        sha: CommitSha(fields[i]),
        parentShas: fields[i + 1].isEmpty
            ? const []
            : fields[i + 1].split(' ').map(CommitSha.new).toList(),
        author: CommitSignature(
          fields[i + 2],
          fields[i + 3],
          DateTime.parse(fields[i + 4]),
        ),
        committer: CommitSignature(
          fields[i + 5],
          fields[i + 6],
          DateTime.parse(fields[i + 7]),
        ),
        summary: fields[i + 8],
        message: fields[i + 9].isEmpty
            ? fields[i + 8]
            : '${fields[i + 8]}\n\n${fields[i + 9]}',
      );
    }
  }

  @override
  Future<List<Branch>> getBranches(RepoLocation repo) async {
    final args = [
      'for-each-ref',
      '--format=%(refname)%00%(objectname)%00%(HEAD)%00%(upstream)%00%(upstream:track)',
      'refs/heads',
      'refs/remotes',
    ];
    final stdout = await _runner.run(repo.path, args);
    if (stdout.trim().isEmpty) return [];

    final lines = stdout.split('\n');
    final branches = <Branch>[];
    final aheadBehindRe =
        RegExp(r'(?:ahead (\d+))?(?:.*?behind (\d+))?');

    for (final line in lines) {
      if (line.isEmpty) continue;
      final fields = line.split('\x00');
      if (fields.length < 5) continue;

      final refname = fields[0];
      final sha = fields[1];
      final headMarker = fields[2];
      final upstream = fields[3];
      final track = fields[4];

      String name;
      bool isRemote;
      if (refname.startsWith('refs/heads/')) {
        name = refname.substring('refs/heads/'.length);
        isRemote = false;
      } else if (refname.startsWith('refs/remotes/')) {
        name = refname.substring('refs/remotes/'.length);
        isRemote = true;
      } else {
        continue;
      }

      int ahead = 0;
      int behind = 0;
      if (track.isNotEmpty) {
        final m = aheadBehindRe.firstMatch(track);
        if (m != null) {
          ahead = int.tryParse(m.group(1) ?? '') ?? 0;
          behind = int.tryParse(m.group(2) ?? '') ?? 0;
        }
      }

      branches.add(Branch(
        name: name,
        fullName: refname,
        isRemote: isRemote,
        isCurrent: headMarker == '*',
        tipSha: sha.isNotEmpty ? CommitSha(sha) : null,
        upstreamFullName: upstream.isNotEmpty ? upstream : null,
        ahead: ahead,
        behind: behind,
      ));
    }

    return branches;
  }

  @override
  Future<List<Tag>> getTags(RepoLocation repo) async {
    final args = [
      'for-each-ref',
      '--format=%(refname:short)%00%(refname)%00%(*objectname)%00%(objectname)%00%(objecttype)',
      'refs/tags',
    ];
    final stdout = await _runner.run(repo.path, args);
    if (stdout.trim().isEmpty) return [];

    final lines = stdout.split('\n');
    final tags = <Tag>[];

    for (final line in lines) {
      if (line.isEmpty) continue;
      final fields = line.split('\x00');
      if (fields.length < 5) continue;

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
    final branchArgs = [
      'for-each-ref',
      '--format=%(refname)%00%(objectname)%00%(HEAD)%00%(upstream)%00%(upstream:track)',
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
        final fields = line.split('\x00');
        if (fields.length < 5) continue;

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

        int ahead = 0;
        int behind = 0;
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
    // git stash list exits 0 even with an empty stash; empty output = no stashes.
    final stdout = await _runner.run(
        repo.path, ['stash', 'list', '--format=%H%x00%gd%x00%gs%x00%ai']);
    if (stdout.trim().isEmpty) return [];

    final stashes = <Stash>[];
    final indexRe = RegExp(r'stash@\{(\d+)\}');

    for (final line in stdout.split('\n')) {
      if (line.isEmpty) continue;
      final fields = line.split('\x00');
      if (fields.length < 4) continue;

      final sha = fields[0];
      final reflogSelector = fields[1]; // e.g., stash@{0}
      final message = fields[2];
      final dateStr = fields[3];

      final indexMatch = indexRe.firstMatch(reflogSelector);
      final index = indexMatch != null ? int.parse(indexMatch.group(1)!) : 0;

      DateTime createdAt;
      try {
        createdAt = DateTime.parse(dateStr);
      } catch (_) {
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
  Future<DiffResult> getDiff(RepoLocation repo, DiffSpec spec) =>
      throw UnimplementedError();

  @override
  Future<List<FileTreeEntry>> getFileTree(
          RepoLocation repo, CommitSha sha, String path) =>
      throw UnimplementedError();
}
