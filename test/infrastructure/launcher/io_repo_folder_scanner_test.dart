import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/launcher/io_repo_folder_scanner.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('gitopen_scan_');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('returns immediate subdirs with a .git directory or file, sorted',
      () async {
    // a/.git (directory) — a normal clone.
    Directory(p.join(root.path, 'a', '.git')).createSync(recursive: true);
    // c/.git (file) — a worktree/submodule.
    Directory(p.join(root.path, 'c')).createSync();
    File(p.join(root.path, 'c', '.git')).writeAsStringSync('gitdir: ../x');
    // b — a plain folder, not a repo.
    Directory(p.join(root.path, 'b')).createSync();
    // loose.txt — a file, not a directory.
    File(p.join(root.path, 'loose.txt')).writeAsStringSync('x');

    final repos =
        await const IoRepoFolderScanner().findRepositories(root.path);

    expect(repos, [p.join(root.path, 'a'), p.join(root.path, 'c')]);
  });

  test('returns empty for a non-existent parent', () async {
    final missing = p.join(root.path, 'nope');
    expect(
      await const IoRepoFolderScanner().findRepositories(missing),
      isEmpty,
    );
  });
}
