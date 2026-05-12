import 'dart:io';
import 'package:path/path.dart' as p;

class RepoFixture {
  final String path;
  String headSha;
  RepoFixture._(this.path, this.headSha);

  static Future<RepoFixture> empty() async {
    final dir = Directory.systemTemp.createTempSync('gitopen-test-');
    await _git(dir.path, ['init', '-q', '-b', 'master']);
    await _git(dir.path, ['config', 'user.email', 'test@example.com']);
    await _git(dir.path, ['config', 'user.name', 'Test']);
    await _git(dir.path, ['config', 'commit.gpgsign', 'false']);
    return RepoFixture._(dir.path, '');
  }

  static Future<RepoFixture> withLinearHistory(int commits) async {
    if (commits < 1) throw ArgumentError.value(commits, 'commits');
    final f = await empty();
    for (var i = 0; i < commits; i++) {
      final file = File(p.join(f.path, 'file_$i.txt'));
      await file.writeAsString('content $i\n');
      await _git(f.path, ['add', 'file_$i.txt']);
      await _git(f.path, ['commit', '-q', '-m', 'commit $i']);
    }
    final headOut = await _git(f.path, ['rev-parse', 'HEAD']);
    f.headSha = headOut.trim();
    return f;
  }

  static Future<RepoFixture> withFileRemote() async {
    final origin = await withLinearHistory(3);
    final local = await empty();
    await _git(local.path, ['remote', 'add', 'origin', origin.path]);
    return local;
  }

  static Future<RepoFixture> withBranches() async {
    final f = await withLinearHistory(3);
    await _git(f.path, ['checkout', '-q', '-b', 'feature']);
    final file = File(p.join(f.path, 'feature.txt'));
    await file.writeAsString('feature\n');
    await _git(f.path, ['add', 'feature.txt']);
    await _git(f.path, ['commit', '-q', '-m', 'on feature']);
    await _git(f.path, ['checkout', '-q', 'master']);
    return f;
  }

  Future<void> dispose() async {
    try {
      await Directory(path).delete(recursive: true);
    } catch (_) {}
  }

  static Future<String> _git(String cwd, List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: cwd);
    if (r.exitCode != 0) {
      throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
    }
    return r.stdout.toString();
  }
}
