import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_commit_template_reader.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';
import 'package:path/path.dart' as p;

import '../../_helpers/repo_fixture.dart';

final class _HomeRunner extends GitProcessRunner {
  _HomeRunner(this.home);

  final String home;

  @override
  Future<String> run(
    String workingDir,
    List<String> args, {
    Duration? timeout,
  }) async {
    final result = await Process.run(
      'git',
      args,
      workingDirectory: workingDir,
      environment: {'HOME': home},
    );
    if (result.exitCode != 0) {
      throw GitProcessException(args, result.exitCode, '${result.stderr}');
    }
    return result.stdout.toString();
  }
}

void main() {
  test('reads a relative commit template and strips comment lines', () async {
    final fixture = await RepoFixture.withLinearHistory(1);
    try {
      await File(
        p.join(fixture.path, 'template.txt'),
      ).writeAsString('Subject\n# guidance\n\nBody\n');
      await Process.run(
        'git',
        ['config', 'commit.template', 'template.txt'],
        workingDirectory: fixture.path,
      );
      final repo = RepoLocation(RepoId.newId(), fixture.path, 'test');
      expect(await GitCliCommitTemplateReader().read(repo), 'Subject\n\nBody');
    } finally {
      await fixture.dispose();
    }
  });

  test('reads a tilde path through git config --path', () async {
    final fixture = await RepoFixture.withLinearHistory(1);
    try {
      final home = await Directory(p.join(fixture.path, 'home')).create();
      await File(
        p.join(home.path, 'template.txt'),
      ).writeAsString('Tilde subject\n# comment\n');
      await Process.run(
        'git',
        ['config', 'commit.template', '~/template.txt'],
        workingDirectory: fixture.path,
      );
      final repo = RepoLocation(RepoId.newId(), fixture.path, 'test');
      final template = await GitCliCommitTemplateReader(
        runner: _HomeRunner(home.path),
      ).read(repo);
      expect(template, 'Tilde subject');
    } finally {
      await fixture.dispose();
    }
  });
}
