import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/domain/status/repo_status.dart';
import 'package:gitopen/domain/status/working_file_entry.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';

/// Reads and parses `git status --porcelain=v2` for the read-operations
/// facade.  Moved verbatim from `GitCliReadOperations`.
final class GitCliStatusReader {
  GitCliStatusReader(this._runner);
  final GitProcessRunner _runner;

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
}
