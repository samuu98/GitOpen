import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_read_operations.dart';
import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) =>
      RepoLocation(RepoId.newId(), f.path, 'test');

  group('GitCliReadOperations refs', () {
    test('getBranches lists local branches with current marker', () async {
      final f = await RepoFixture.withBranches();
      try {
        final sut = GitCliReadOperations();
        final branches = await sut.getBranches(loc(f));
        expect(branches.any((b) => b.name == 'feature'), isTrue);
        final localCurrent = branches.where((b) => !b.isRemote && b.isCurrent);
        expect(localCurrent, hasLength(1));
        expect(localCurrent.first.name, 'master');
      } finally { await f.dispose(); }
    });

    test('getTags lists tags', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        await Process.run('git', ['tag', 'v1.0'], workingDirectory: f.path);
        final sut = GitCliReadOperations();
        final tags = await sut.getTags(loc(f));
        expect(tags, hasLength(1));
        expect(tags.first.name, 'v1.0');
      } finally { await f.dispose(); }
    });

    test('getRemotes returns empty when none', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        final sut = GitCliReadOperations();
        final remotes = await sut.getRemotes(loc(f));
        expect(remotes, isEmpty);
      } finally { await f.dispose(); }
    });

    test('getRemotes parses `git remote -v` (name TAB url SP qualifier)',
        () async {
      // Regression: an earlier parser expected two tabs per line and so
      // dropped every entry — the REMOTES section in the sidebar always
      // looked empty even when origin existed.
      final origin = await RepoFixture.withLinearHistory(1);
      final f = await RepoFixture.withLinearHistory(1);
      try {
        await Process.run('git', ['remote', 'add', 'origin', origin.path],
            workingDirectory: f.path);
        await Process.run('git', ['remote', 'add', 'mirror', origin.path],
            workingDirectory: f.path);
        await Process.run('git', ['fetch', 'origin'], workingDirectory: f.path);
        final sut = GitCliReadOperations();
        final remotes = await sut.getRemotes(loc(f));
        expect(remotes.map((r) => r.name), unorderedEquals(['origin', 'mirror']));
        final originRemote = remotes.firstWhere((r) => r.name == 'origin');
        expect(originRemote.url, origin.path);
        expect(originRemote.branches, isNotEmpty,
            reason: 'fetched origin should expose its branches');
      } finally {
        await f.dispose();
        await origin.dispose();
      }
    });

    test('getStashes returns empty when none', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        final sut = GitCliReadOperations();
        final stashes = await sut.getStashes(loc(f));
        expect(stashes, isEmpty);
      } finally { await f.dispose(); }
    });
  });
}
