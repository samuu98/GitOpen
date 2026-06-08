import 'dart:io';
import 'package:path/path.dart' as p;

class RepoFixture {
  RepoFixture._(this.path, this.headSha);
  final String path;
  String headSha;

  /// Sha of the first (oldest) commit, set by fixtures that need to assert
  /// against a non-HEAD commit (e.g. blame attribution).  Empty otherwise.
  String firstSha = '';

  /// Per-commit SHAs (oldest-first) for fixtures that need to address every
  /// commit individually, e.g. [withRebaseHistory]. Empty otherwise.
  List<String> rebaseShas = const [];

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

  /// Linear history whose commits carry distinct messages and authors so
  /// search-by-message / search-by-author / search-by-content can be asserted
  /// against known data.  Commits are created oldest-first:
  ///   0: "Add login feature"      author Alice  (adds login.txt -> 'token')
  ///   1: "Fix logout bug"         author Bob    (adds logout.txt)
  ///   2: "Refactor session store" author Alice  (adds session.txt)
  static Future<RepoFixture> withSearchableHistory() async {
    final f = await empty();

    Future<void> make(
      String fileName,
      String contents,
      String message,
      String authorName,
      String authorEmail,
    ) async {
      await File(p.join(f.path, fileName)).writeAsString(contents);
      await _git(f.path, ['add', fileName]);
      await _git(f.path, [
        'commit',
        '-q',
        '-m',
        message,
        '--author=$authorName <$authorEmail>',
      ]);
    }

    await make(
      'login.txt',
      'auth token = secret\n',
      'Add login feature',
      'Alice',
      'alice@example.com',
    );
    await make(
      'logout.txt',
      'clear cookies\n',
      'Fix logout bug',
      'Bob',
      'bob@example.com',
    );
    await make(
      'session.txt',
      'store session\n',
      'Refactor session store',
      'Alice',
      'alice@example.com',
    );

    f.headSha = (await _git(f.path, ['rev-parse', 'HEAD'])).trim();
    return f;
  }

  /// History exercising file-history (`--follow`) and blame.  Built
  /// oldest-first:
  ///   0: "create app"   adds app.txt ('line one\n') + other.txt
  ///   1: "edit app"     app.txt -> 'line one\nline two\n'
  ///   2: "rename app"   `git mv app.txt main.txt` (pure rename)
  ///   3: "edit main"    main.txt -> 'line one\nline two CHANGED\n'
  /// `other.txt` is touched only in commit 0 so its history must exclude
  /// every app/main commit.  After commit 2 the file is named `main.txt`;
  /// `--follow main.txt` must still report all four app/main commits.
  static Future<RepoFixture> withFileHistory() async {
    final f = await empty();

    Future<void> commit(String message) async {
      await _git(f.path, ['add', '-A']);
      await _git(f.path, ['commit', '-q', '-m', message]);
    }

    final app = File(p.join(f.path, 'app.txt'));
    await app.writeAsString('line one\n');
    await File(p.join(f.path, 'other.txt')).writeAsString('unrelated\n');
    await commit('create app');

    await app.writeAsString('line one\nline two\n');
    await commit('edit app');

    await _git(f.path, ['mv', 'app.txt', 'main.txt']);
    await commit('rename app');

    await File(p.join(f.path, 'main.txt'))
        .writeAsString('line one\nline two CHANGED\n');
    await commit('edit main');

    f.headSha = (await _git(f.path, ['rev-parse', 'HEAD'])).trim();
    return f;
  }

  /// Repo with a two-line file authored by two different people, so blame
  /// can be asserted per-line (sha + author).  Built oldest-first:
  ///   0: Alice adds blame.txt with a single line 'alpha\n'
  ///   1: Bob appends 'beta\n'  -> file is 'alpha\nbeta\n'
  /// Line 1 is attributed to Alice's commit, line 2 to Bob's.
  static Future<RepoFixture> withBlameHistory() async {
    final f = await empty();
    final file = File(p.join(f.path, 'blame.txt'));

    await file.writeAsString('alpha\n');
    await _git(f.path, ['add', 'blame.txt']);
    await _git(f.path, [
      'commit',
      '-q',
      '-m',
      'add alpha',
      '--author=Alice <alice@example.com>',
    ]);
    final firstSha = (await _git(f.path, ['rev-parse', 'HEAD'])).trim();

    await file.writeAsString('alpha\nbeta\n');
    await _git(f.path, ['add', 'blame.txt']);
    await _git(f.path, [
      'commit',
      '-q',
      '-m',
      'add beta',
      '--author=Bob <bob@example.com>',
    ]);
    final secondSha = (await _git(f.path, ['rev-parse', 'HEAD'])).trim();

    f
      ..headSha = secondSha
      ..firstSha = firstSha;
    return f;
  }

  /// Linear history of four commits for interactive-rebase tests. Built
  /// oldest-first, each commit adding a distinct file with known content:
  ///   c0 "c0 base"  adds c0.txt -> 'c0\n'
  ///   c1 "c1"       adds c1.txt -> 'c1\n'
  ///   c2 "c2"       adds c2.txt -> 'c2\n'
  ///   c3 "c3"       adds c3.txt -> 'c3\n'
  /// The per-commit SHAs are exposed via [rebaseShas] (oldest-first), so a
  /// test can build a todo plan over `c1..c3` with `c0` as the rebase base.
  static Future<RepoFixture> withRebaseHistory() async {
    final f = await empty();
    final shas = <String>[];
    for (var i = 0; i < 4; i++) {
      await File(p.join(f.path, 'c$i.txt')).writeAsString('c$i\n');
      await _git(f.path, ['add', 'c$i.txt']);
      final msg = i == 0 ? 'c0 base' : 'c$i';
      await _git(f.path, ['commit', '-q', '-m', msg]);
      shas.add((await _git(f.path, ['rev-parse', 'HEAD'])).trim());
    }
    f
      ..rebaseShas = shas
      ..firstSha = shas.first
      ..headSha = shas.last;
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

  /// Repo whose HEAD is a real (`--no-ff`) merge commit with two parents.
  /// `master` adds master.txt, `feature` adds feature.txt; the merge
  /// introduces feature.txt relative to its FIRST parent (master).
  static Future<RepoFixture> withMergeCommit() async {
    final f = await empty();
    await File(p.join(f.path, 'file_0.txt')).writeAsString('content 0\n');
    await _git(f.path, ['add', 'file_0.txt']);
    await _git(f.path, ['commit', '-q', '-m', 'commit 0']);

    await _git(f.path, ['checkout', '-q', '-b', 'feature']);
    await File(p.join(f.path, 'feature.txt')).writeAsString('feature\n');
    await _git(f.path, ['add', 'feature.txt']);
    await _git(f.path, ['commit', '-q', '-m', 'on feature']);

    await _git(f.path, ['checkout', '-q', 'master']);
    await File(p.join(f.path, 'master.txt')).writeAsString('master\n');
    await _git(f.path, ['add', 'master.txt']);
    await _git(f.path, ['commit', '-q', '-m', 'on master']);

    await _git(f.path, [
      'merge',
      '-q',
      '--no-ff',
      '-m',
      'merge feature',
      'feature',
    ]);
    f.headSha = (await _git(f.path, ['rev-parse', 'HEAD'])).trim();
    return f;
  }

  Future<void> dispose() async {
    try {
      await Directory(path).delete(recursive: true);
    } on Object {
      // Best-effort cleanup; ignore failures (e.g. locked files on Windows).
    }
  }

  static Future<String> _git(String cwd, List<String> args) async {
    final r = await Process.run('git', args, workingDirectory: cwd);
    if (r.exitCode != 0) {
      throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
    }
    return r.stdout.toString();
  }
}
