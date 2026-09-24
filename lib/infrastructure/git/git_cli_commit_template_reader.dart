import 'dart:io';

import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:path/path.dart' as p;

class GitCliCommitTemplateReader {
  GitCliCommitTemplateReader({GitProcessRunner? runner})
    : _runner = runner ?? GitProcessRunner();

  final GitProcessRunner _runner;

  Future<String?> read(RepoLocation repo) async {
    try {
      final configured = (await _runner.run(
        repo.path,
        ['config', '--path', '--get', 'commit.template'],
      )).trim();
      if (configured.isEmpty) return null;
      // Git expands ~ for --path. A relative result is relative to the
      // command's working directory, which here is the repository root.
      final path = p.isAbsolute(configured)
          ? configured
          : p.join(repo.path, configured);
      final contents = await File(path).readAsString();
      final lines = contents.replaceAll('\r\n', '\n').split('\n')
        ..removeWhere((line) => line.trimLeft().startsWith('#'));
      return lines.join('\n').trimRight();
    } on GitProcessException {
      return null;
    } on FileSystemException {
      return null;
    }
  }
}
