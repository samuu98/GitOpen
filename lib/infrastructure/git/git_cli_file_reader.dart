import 'dart:convert';
import 'dart:io';

import 'package:gitopen/domain/blame/blame_line.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/diff/diff_result.dart';
import 'package:gitopen/domain/diff/diff_spec.dart';
import 'package:gitopen/domain/files/file_tree_entry.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/blame_parser.dart';
import 'package:gitopen/infrastructure/git/diff_parser.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:path/path.dart' as p;

/// Reads file-level data (diffs, trees, blame, working-tree bytes) for the
/// read-operations facade.  Moved verbatim from `GitCliReadOperations`.
final class GitCliFileReader {
  GitCliFileReader(this._runner);
  final GitProcessRunner _runner;

  Future<DiffResult> getDiff(
    RepoLocation repo,
    DiffSpec spec, {
    String? path,
  }) async {
    // `core.quotepath=false` makes git print non-ASCII paths raw (UTF-8)
    // instead of C-quote-escaping them ("caf\303\250.txt") — the quoted form
    // doesn't match the parser's `diff --git a/<path> b/<path>` regex and the
    // file would silently vanish from the diff.
    const unquoted = ['-c', 'core.quotepath=false'];
    final args = switch (spec) {
      DiffSpecCommitVsParent(:final commitSha) => [
          // `--first-parent -m` makes merge commits emit a normal 2-way diff
          // against their first parent (Fork/GitKraken default) instead of a
          // combined diff (diff --cc / @@@) the unified parser can't read.
          // It is a no-op on normal and root commits, so it is safe for all
          // single-commit diffs.
          ...unquoted,
          'show', commitSha.value, '--first-parent', '-m',
          '--format=', '--raw', '-p', '--no-color',
        ],
      DiffSpecCommitVsCommit(:final from, :final to) => [
          ...unquoted,
          'diff', '${from.value}..${to.value}', '--raw', '-p', '--no-color',
        ],
      DiffSpecIndexVsHead() => [
          ...unquoted,
          'diff', '--cached', '--raw', '-p', '--no-color',
        ],
      DiffSpecWorkingTreeVsIndex() => [
          ...unquoted,
          'diff', '--raw', '-p', '--no-color',
        ],
    };
    final stdout = await _runner.run(repo.path, [
      ...args,
      if (path != null) ...['--', path],
    ]);
    return DiffParser(stdout).parse();
  }

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
    return BlameParser(stdout).parse();
  }

  Future<String> readWorkingFile(
    RepoLocation repo,
    String relativePath,
  ) async {
    // Reads straight from disk (not via git) so we get the exact working-tree
    // bytes including any conflict markers git wrote during a failed merge.
    // Decode lenient: a stray non-UTF-8 byte must not crash the editor — the
    // parser simply won't find markers and the UI falls back to the external
    // editor.
    final file = File(p.join(repo.path, relativePath));
    final bytes = await file.readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  FileTreeKind _mapTreeKind(String type, String mode) {
    if (type == 'tree') return FileTreeKind.tree;
    if (type == 'commit') return FileTreeKind.submodule;
    if (mode == '120000') return FileTreeKind.symlink;
    return FileTreeKind.blob;
  }
}
