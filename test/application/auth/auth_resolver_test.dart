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
    Set<String> emails = const {},
  }) async {
    final pid = id ?? 'gen-${_byId.length}';
    final profile = AuthProfile(
      id: pid,
      host: host,
      username: username,
      spec: spec,
      emails: emails,
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

class _FakeRemoteUrl implements RemoteUrlReader {
  _FakeRemoteUrl(this.url);
  final String? url;
  @override
  Future<String?> remoteUrl(RepoLocation repo, String remote) async => url;
}

class _FakeIdentity implements RepoIdentityReader {
  _FakeIdentity(this.email);
  final String? email;
  @override
  Future<String?> effectiveEmail(RepoLocation repo) async => email;
}

class _CountingRemoteUrl implements RemoteUrlReader {
  _CountingRemoteUrl(this.url);
  final String? url;
  int calls = 0;
  @override
  Future<String?> remoteUrl(RepoLocation repo, String remote) async {
    calls++;
    return url;
  }
}

class _CountingIdentity implements RepoIdentityReader {
  _CountingIdentity(this.email);
  final String? email;
  int calls = 0;
  @override
  Future<String?> effectiveEmail(RepoLocation repo) async {
    calls++;
    return email;
  }
}

AuthProfile profileWithEmails(String id, String user, Set<String> emails) =>
    AuthProfile(
      id: id,
      host: 'github.com',
      username: user,
      spec: AuthHttpsPat(username: user, token: 'tok-$id'),
      emails: emails,
    );

/// Builds a resolver. By default it uses the real git-CLI remote reader (the
/// host-extraction tests are integration tests against real repos); pass
/// [remoteUrl]/[identity] fakes for the pure email-match tests.
AuthResolver resolver(
  AuthProfileStore store, {
  String? Function(String repoId)? bindingLookup,
  RemoteUrlReader? remoteUrl,
  RepoIdentityReader? identity,
}) => AuthResolver(
  store,
  remoteUrl: remoteUrl ?? GitRemoteUrlReader(),
  bindingLookup: bindingLookup,
  identity: identity,
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

    test(
      'binding to a missing profile falls through to host fallback',
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
      },
    );
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

  group('AuthResolver identity (email) match', () {
    AuthProfile withEmails(
      String id,
      String host,
      String user,
      Set<String> emails,
    ) => AuthProfile(
      id: id,
      host: host,
      username: user,
      spec: AuthHttpsPat(username: user, token: 'tok-$id'),
      emails: emails,
    );

    test(
      'email match picks the owning profile among several for the host',
      () async {
        final store = FakeAuthProfileStore([
          withEmails('p1', 'github.com', 'alice', {'alice@personal.dev'}),
          withEmails('p2', 'github.com', 'work', {'giuseppe@work.com'}),
        ]);
        final r = resolver(
          store,
          remoteUrl: _FakeRemoteUrl('https://github.com/x/y.git'),
          identity: _FakeIdentity('giuseppe@work.com'),
        );
        final resolved = await r.resolveForRepo(locAt('/any'));
        expect(resolved?.id, 'p2');
      },
    );

    test('match is case-insensitive', () async {
      final store = FakeAuthProfileStore([
        withEmails('p1', 'github.com', 'alice', {'alice@personal.dev'}),
        withEmails('p2', 'github.com', 'work', {'giuseppe@work.com'}),
      ]);
      final r = resolver(
        store,
        remoteUrl: _FakeRemoteUrl('https://github.com/x/y.git'),
        identity: _FakeIdentity('Alice@Personal.DEV'),
      );
      final resolved = await r.resolveForRepo(locAt('/any'));
      expect(resolved?.id, 'p1');
    });

    test('explicit binding wins over an email match', () async {
      final store = FakeAuthProfileStore([
        withEmails('p1', 'github.com', 'alice', {'shared@x.com'}),
        withEmails('p2', 'github.com', 'work', {'shared@x.com'}),
      ]);
      final r = resolver(
        store,
        bindingLookup: (_) => 'p1',
        remoteUrl: _FakeRemoteUrl('https://github.com/x/y.git'),
        identity: _FakeIdentity('shared@x.com'),
      );
      final resolved = await r.resolveForRepo(locAt('/any'));
      expect(resolved?.id, 'p1');
    });

    test(
      'an email matching >1 profile is ambiguous -> falls through to null',
      () async {
        final store = FakeAuthProfileStore([
          withEmails('p1', 'github.com', 'a', {'dup@x.com'}),
          withEmails('p2', 'github.com', 'b', {'dup@x.com'}),
        ]);
        final r = resolver(
          store,
          remoteUrl: _FakeRemoteUrl('https://github.com/x/y.git'),
          identity: _FakeIdentity('dup@x.com'),
        );
        expect(await r.resolveForRepo(locAt('/any')), isNull);
      },
    );

    test('no email match falls back to single-profile-per-host', () async {
      final store = FakeAuthProfileStore([
        withEmails('p1', 'github.com', 'alice', {'alice@personal.dev'}),
      ]);
      final r = resolver(
        store,
        remoteUrl: _FakeRemoteUrl('https://github.com/x/y.git'),
        identity: _FakeIdentity('nobody@nope.com'),
      );
      final resolved = await r.resolveForRepo(locAt('/any'));
      expect(resolved?.id, 'p1');
    });

    test('an unset email skips the identity step', () async {
      final store = FakeAuthProfileStore([
        withEmails('p1', 'github.com', 'a', {'a@x.com'}),
        withEmails('p2', 'github.com', 'b', {'b@x.com'}),
      ]);
      final r = resolver(
        store,
        remoteUrl: _FakeRemoteUrl('https://github.com/x/y.git'),
        identity: _FakeIdentity(null),
      );
      expect(await r.resolveForRepo(locAt('/any')), isNull);
    });

    test('email match is host-scoped', () async {
      final store = FakeAuthProfileStore([
        withEmails('p1', 'github.com', 'alice', {'me@x.com'}),
        withEmails('p2', 'gitlab.com', 'alice', {'me@x.com'}),
      ]);
      final r = resolver(
        store,
        remoteUrl: _FakeRemoteUrl('https://gitlab.com/x/y.git'),
        identity: _FakeIdentity('me@x.com'),
      );
      final resolved = await r.resolveForRepo(locAt('/any'));
      expect(resolved?.id, 'p2');
    });
  });

  group('AuthResolver caching and email-skip', () {
    test(
      'does not read the email when the host has a single candidate',
      () async {
        final store = FakeAuthProfileStore([
          profile('p1', 'github.com', 'alice'),
        ]);
        final identity = _CountingIdentity('whoever@x.com');
        final r = resolver(
          store,
          remoteUrl: _FakeRemoteUrl('https://github.com/x/y.git'),
          identity: identity,
        );
        final resolved = await r.resolveForRepo(locAt('/any'));
        expect(resolved?.id, 'p1');
        expect(identity.calls, 0);
      },
    );

    test(
      'reads the email to disambiguate when there are multiple candidates',
      () async {
        final store = FakeAuthProfileStore([
          profileWithEmails('p1', 'a', {'a@x.com'}),
          profileWithEmails('p2', 'b', {'b@x.com'}),
        ]);
        final identity = _CountingIdentity('b@x.com');
        final r = resolver(
          store,
          remoteUrl: _FakeRemoteUrl('https://github.com/x/y.git'),
          identity: identity,
        );
        final resolved = await r.resolveForRepo(locAt('/any'));
        expect(resolved?.id, 'p2');
        expect(identity.calls, 1);
      },
    );

    test('caches the remote url and email across resolves', () async {
      final store = FakeAuthProfileStore([
        profileWithEmails('p1', 'a', {'a@x.com'}),
        profileWithEmails('p2', 'b', {'b@x.com'}),
      ]);
      final remoteUrl = _CountingRemoteUrl('https://github.com/x/y.git');
      final identity = _CountingIdentity('b@x.com');
      final r = resolver(store, remoteUrl: remoteUrl, identity: identity);

      await r.resolveForRepo(locAt('/any'));
      await r.resolveForRepo(locAt('/any'));

      expect(remoteUrl.calls, 1);
      expect(identity.calls, 1);
    });

    test('clearCache forces the git facts to be re-read', () async {
      final store = FakeAuthProfileStore([
        profile('p1', 'github.com', 'alice'),
      ]);
      final remoteUrl = _CountingRemoteUrl('https://github.com/x/y.git');
      final r = resolver(
        store,
        remoteUrl: remoteUrl,
        identity: _CountingIdentity(null),
      );

      await r.resolveForRepo(locAt('/any'));
      r.clearCache();
      await r.resolveForRepo(locAt('/any'));

      expect(remoteUrl.calls, 2);
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
