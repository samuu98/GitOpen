import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/git/git_process_runner.dart';

import '../../_helpers/repo_fixture.dart';

void main() {
  test('run returns stdout for a successful command', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      final out = await GitProcessRunner().run(f.path, ['rev-parse', 'HEAD']);
      expect(out.trim(), hasLength(40));
    } finally {
      await f.dispose();
    }
  });

  test('run honours a generous timeout without tripping', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      final out = await GitProcessRunner().run(
        f.path,
        ['rev-parse', 'HEAD'],
        timeout: const Duration(seconds: 30),
      );
      expect(out.trim(), isNotEmpty);
    } finally {
      await f.dispose();
    }
  });

  test('run kills the child and throws when the timeout is exceeded', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      // `hash-object --stdin` blocks reading stdin, which run() never closes,
      // so the child outlives any timeout deterministically. Racing a fast
      // command (e.g. rev-parse) against a tiny timeout is flaky: on fast
      // Linux runners the process exits before the timeout is observed.
      await expectLater(
        GitProcessRunner().run(
          f.path,
          ['hash-object', '--stdin'],
          timeout: const Duration(milliseconds: 200),
        ),
        throwsA(isA<GitProcessException>()),
      );
    } finally {
      await f.dispose();
    }
  });

  test('run throws GitProcessException on a non-zero exit', () async {
    final f = await RepoFixture.empty();
    try {
      await expectLater(
        GitProcessRunner().run(f.path, ['rev-parse', '--verify', 'nope']),
        throwsA(isA<GitProcessException>()),
      );
    } finally {
      await f.dispose();
    }
  });
}
