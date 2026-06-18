import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import '../_helpers/repo_fixture.dart';

void main() {
  test('reports path, origin url and effective identity', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      await Process.run(
        'git',
        ['remote', 'add', 'origin', 'https://github.com/o/r.git'],
        workingDirectory: f.path,
      );
      await Process.run('git', ['config', 'user.name', 'Tester'],
          workingDirectory: f.path);
      await Process.run('git', ['config', 'user.email', 't@e.com'],
          workingDirectory: f.path);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final repo = RepoLocation(const RepoId('r'), f.path, 'r');
      final info = await container.read(repoInfoProvider(repo).future);

      expect(info.path, f.path);
      expect(info.originUrl, 'https://github.com/o/r.git');
      expect(info.userName, 'Tester');
      expect(info.userEmail, 't@e.com');
    } finally {
      await f.dispose();
    }
  });
}
