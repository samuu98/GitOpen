import '../../application/git/git_read_operations.dart';
import '../../domain/commits/commit_info.dart';
import '../../domain/commits/commit_sha.dart';
import '../../domain/commits/commit_signature.dart';
import '../../domain/diff/diff_hunk.dart';
import '../../domain/diff/diff_line.dart';
import '../../domain/diff/diff_result.dart';
import '../../domain/diff/diff_spec.dart';
import '../../domain/diff/file_diff.dart';
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
  Future<DiffResult> getDiff(RepoLocation repo, DiffSpec spec) async {
    final args = switch (spec) {
      DiffSpecCommitVsParent(:final commitSha) => [
          'show', commitSha.value, '--format=', '--raw', '-p', '--no-color',
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

    final files = <FileDiff>[];
    final rawByPath = <String, _RawEntry>{};

    final lines = stdout.split('\n');
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
          rawByPath[path] = _RawEntry(letter, oldPath);
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
      final raw = rawByPath[newPath];
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
                oldLine: null,
                newLine: newLine++,
                content: line.substring(1)));
            added++;
            break;
          case '-':
            if (line.startsWith('---')) {
              i++;
              continue;
            }
            hunkLines.add(DiffLine(
                kind: DiffLineKind.deletion,
                oldLine: oldLine++,
                newLine: null,
                content: line.substring(1)));
            deleted++;
            break;
          case ' ':
            hunkLines.add(DiffLine(
                kind: DiffLineKind.context,
                oldLine: oldLine++,
                newLine: newLine++,
                content: line.substring(1)));
            break;
          case '\\':
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

      files.add(FileDiff(
        path: newPath,
        oldPath: raw?.oldPath,
        changeKind: changeKind,
        isBinary: isBinary,
        linesAdded: added,
        linesDeleted: deleted,
        hunks: hunks,
      ));
    }

    return DiffResult(files: files);
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

  FileTreeKind _mapTreeKind(String type, String mode) {
    if (type == 'tree') return FileTreeKind.tree;
    if (type == 'commit') return FileTreeKind.submodule;
    if (mode == '120000') return FileTreeKind.symlink;
    return FileTreeKind.blob;
  }
}

class _RawEntry {
  final String status;
  final String? oldPath;
  _RawEntry(this.status, this.oldPath);
}
