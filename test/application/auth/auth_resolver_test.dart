import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_profile_store.dart';
import 'package:gitopen/application/auth/auth_resolver.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_remote_url_reader.dart';
import '../../_helpers/repo_fixture.dart';

/// Minimal in-memory [AuthProfileStore] for resolver tests. Keyed by id;
/// [forHost] filters by host. `upsert`/`delete` are implemented enough to
/// seed fixtures.
class FakeAuthProfileStore implements AuthProfileStore {
  FakeAuthProfileStore([List<AuthProfile> seed = const []]) {
    for (final p in seed) {
      _byId[p.id] = p;
    }
  }
  final Map<String, AuthProfile> _byId = {};

  @override
  Future<List<AuthProfile>> list() async => _byId.values.toList();

  @override
  Future<AuthProfile?> get(String id) async => _byId[id];

  @override
  Future<List<AuthProfile>> forHost(String host) async =>
      _byId.values.where((p) => p.host == host).toList();

  @override
  Future<AuthProfile> upsert({
    required String host,
    required String username,
    required AuthSpec spec,
    String? id,
  }) async {
    final pid = id ?? 'gen-${_byId.length}';
    final profile = AuthProfile(
      id: pid,
      host: host,
      username: username,
      spec: spec,
    );
    _byId[pid] = profile;
    return profile;
  }

  @override
  Future<void> delete(String id) async => _byId.remove(id);
}

AuthProfile profile(String id, String host, String username) => AuthProfile(
      id: id,
      host: host,
      username: username,
      spec: AuthHttpsPat(username: username, token: 'tok-$id'),
    );

/// Builds a resolver with the real git-CLI remote reader — these are
/// integration tests that exercise host extraction against real repos.
AuthResolver resolver(
  AuthProfileStore store, {
  String? Function(String repoId)? bindingLookup,
}) =>
    AuthResolver(
      store,
      remoteUrl: GitRemoteUrlReader(),
      bindingLookup: bindingLookup,
    );

void main() {
  const repoId = RepoId('repo-1');
  RepoLocation locAt(String path) => RepoLocation(repoId, path, 'test');

  group('AuthResolver per-repo binding', () {
    test('bound profile id wins and is returned', () async {
      final p = profile('p1', 'github.com', 'alice');
      final store = FakeAuthProfileStore([p]);
      final r = resolver(
        store,
        bindingLookup: (id) => id == 'repo-1' ? 'p1' : null,
      );
      // Path need not be a real repo: the binding short-circuits before git.
      final resolved = await r.resolveForRepo(locAt('/nonexistent'));
      expect(resolved, p);
    });

    test('binding to a missing profile falls through to host fallback',
        () async {
      // Store has exactly one profile for the host but the binding points
      // at an id that does not exist -> falls through, then resolves by host.
      final p = profile('real', 'github.com', 'alice');
      final store = FakeAuthProfileStore([p]);
      final r = resolver(
        store,
        bindingLookup: (_) => 'ghost',
      );
      final f = await RepoFixture.empty();
      try {
        await Process.run(
          'git',
          ['remote', 'add', 'origin', 'https://github.com/alice/repo.git'],
          workingDirectory: f.path,
        );
        final resolved = await r.resolveForRepo(locAt(f.path));
        expect(resolved, p);
      } finally {
        await f.dispose();
      }
    });
  });

  group('AuthResolver host fallback (no binding)', () {
    test('single profile for the host is chosen implicitly', () async {
      final p = profile('p1', 'github.com', 'alice');
      final store = FakeAuthProfileStore([p]);
      final r = resolver(store); // default binding -> null
      final f = await RepoFixture.empty();
      try {
        await Process.run(
          'git',
          ['remote', 'add', 'origin', 'https://github.com/alice/repo.git'],
          workingDirectory: f.path,
        );
        final resolved = await r.resolveForRepo(locAt(f.path));
        expect(resolved, p);
      } finally {
        await f.dispose();
      }
    });

    test('extracts host from an ssh-style remote url', () async {
      final p = profile('p1', 'github.com', 'alice');
      final store = FakeAuthProfileStore([p]);
      final r = resolver(store);
      final f = await RepoFixture.empty();
      try {
        await Process.run(
          'git',
          ['remote', 'add', 'origin', 'git@github.com:alice/repo.git'],
          workingDirectory: f.path,
        );
        final resolved = await r.resolveForRepo(locAt(f.path));
        expect(resolved, p);
      } finally {
        await f.dispose();
      }
    });

    test('multiple profiles for the host is ambiguous -> null', () async {
      final store = FakeAuthProfileStore([
        profile('p1', 'github.com', 'alice'),
        profile('p2', 'github.com', 'bob'),
      ]);
      final r = resolver(store);
      final f = await RepoFixture.empty();
      try {
        await Process.run(
          'git',
          ['remote', 'add', 'origin', 'https://github.com/alice/repo.git'],
          workingDirectory: f.path,
        );
        final resolved = await r.resolveForRepo(locAt(f.path));
        expect(resolved, isNull);
      } finally {
        await f.dispose();
      }
    });

    test('no profile for the host -> null', () async {
      final store = FakeAuthProfileStore([
        profile('p1', 'gitlab.com', 'alice'),
      ]);
      final r = resolver(store);
      final f = await RepoFixture.empty();
      try {
        await Process.run(
          'git',
          ['remote', 'add', 'origin', 'https://github.com/alice/repo.git'],
          workingDirectory: f.path,
        );
        final resolved = await r.resolveForRepo(locAt(f.path));
        expect(resolved, isNull);
      } finally {
        await f.dispose();
      }
    });

    test('no origin remote -> host is null -> null', () async {
      final store = FakeAuthProfileStore([
        profile('p1', 'github.com', 'alice'),
      ]);
      final r = resolver(store);
      final f = await RepoFixture.empty();
      try {
        final resolved = await r.resolveForRepo(locAt(f.path));
        expect(resolved, isNull);
      } finally {
        await f.dispose();
      }
    });
  });

  group('AuthResolver.hostFromRepo', () {
    test('returns host for https remote', () async {
      final r = resolver(FakeAuthProfileStore());
      final f = await RepoFixture.empty();
      try {
        await Process.run(
          'git',
          ['remote', 'add', 'origin', 'https://example.org/x/y.git'],
          workingDirectory: f.path,
        );
        final host = await r.hostFromRepo(locAt(f.path), 'origin');
        expect(host, 'example.org');
      } finally {
        await f.dispose();
      }
    });

    test('returns null when the remote does not exist', () async {
      final r = resolver(FakeAuthProfileStore());
      final f = await RepoFixture.empty();
      try {
        final host = await r.hostFromRepo(locAt(f.path), 'origin');
        expect(host, isNull);
      } finally {
        await f.dispose();
      }
    });
  });
}
