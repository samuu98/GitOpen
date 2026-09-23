import 'dart:convert';
import 'dart:io';

import 'package:gitopen/application/git/git_read_operations.dart'
    show kFilePreviewMaxBytes;
import 'package:gitopen/domain/blame/blame_line.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/diff/diff_result.dart';
import 'package:gitopen/domain/diff/diff_spec.dart';
import 'package:gitopen/domain/files/file_content.dart';
import 'package:gitopen/domain/files/file_revision.dart';
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
    bool ignoreWhitespace = false,
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
        'diff',
        '${from.value}..${to.value}',
        '--raw',
        '-p',
        '--no-color',
      ],
      DiffSpecIndexVsHead() => [
        ...unquoted,
        'diff',
        '--cached',
        '--raw',
        '-p',
        '--no-color',
      ],
      DiffSpecWorkingTreeVsIndex() => [
        ...unquoted,
        'diff',
        '--raw',
        '-p',
        '--no-color',
      ],
    };
    final stdout = await _runner.run(repo.path, [
      ...args,
      if (ignoreWhitespace) '-w',
      if (path != null) ...['--', path],
    ]);
    return DiffParser(stdout).parse();
  }

  Future<DiffResult> getStashDiff(RepoLocation repo, int index) async {
    const unquoted = ['-c', 'core.quotepath=false'];
    final stdout = await _runner.run(repo.path, [
      ...unquoted,
      'stash',
      'show',
      '--raw',
      '-p',
      '--no-color',
      'stash@{$index}',
    ]);
    return DiffParser(stdout).parse();
  }

  Future<List<FileTreeEntry>> getFileTree(
    RepoLocation repo,
    CommitSha sha,
    String path, {
    bool recursive = false,
  }) async {
    final ref = path.isEmpty ? sha.value : '${sha.value}:$path';
    final stdout = await _runner.run(repo.path, [
      'ls-tree',
      '-l',
      '-z',
      if (recursive) '-r',
      ref,
    ]);
    final entries = <FileTreeEntry>[];
    for (final line in stdout.split('\x00')) {
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
      entries.add(
        FileTreeEntry(
          name: name,
          fullPath: path.isEmpty ? filePath : '$path/$filePath',
          kind: kind,
          sizeBytes: size,
          containingCommit: sha,
        ),
      );
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

  Future<FileContent> getFileBytes(
    RepoLocation repo,
    FileRevision revision,
    String path, {
    int maxBytes = kFilePreviewMaxBytes,
  }) async {
    if (revision is FileRevisionWorkingTree) {
      final file = File(p.join(repo.path, path));
      if (!file.existsSync()) return FileContent.missing;
      final size = await file.length();
      if (size > maxBytes) return FileContent(exists: true, sizeBytes: size);
      return FileContent(
        exists: true,
        sizeBytes: size,
        bytes: await file.readAsBytes(),
      );
    }
    final rev = switch (revision) {
      FileRevisionAtCommit(:final commitSha) => '${commitSha.value}:$path',
      FileRevisionParentOfCommit(:final commitSha) =>
        '${commitSha.value}^:$path',
      FileRevisionHead() => 'HEAD:$path',
      FileRevisionIndex() => ':$path',
      FileRevisionWorkingTree() => throw StateError('handled above'),
    };
    final int size;
    try {
      final out = await _runner.run(repo.path, ['cat-file', '-s', rev]);
      size = int.parse(out.trim());
    } on GitProcessException {
      // Any failure resolving the rev means "no blob there": unknown path,
      // root commit's missing parent, unborn HEAD. Callers render an
      // absent side, so this is a value, not an error.
      return FileContent.missing;
    }
    if (size > maxBytes) return FileContent(exists: true, sizeBytes: size);
    final bytes = await _runner.runBytes(repo.path, ['cat-file', 'blob', rev]);
    return FileContent(exists: true, sizeBytes: size, bytes: bytes);
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
