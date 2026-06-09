import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/infrastructure/auth/dpapi_storage.dart';
import 'package:gitopen/infrastructure/auth/secure_auth_profile_store.dart';

/// In-memory [DpapiStorage] stand-in.
///
/// [DpapiStorage] is a concrete class with a private constructor, so it cannot
/// be subclassed from a test library. It can, however, be *implemented*: the
/// production code only ever touches its public key/value surface
/// (`read` / `write` / `delete`), and [SecureAuthProfileStore] accepts any
/// [DpapiStorage] via its constructor. This fake backs that surface with a
/// plain [Map], with no DPAPI / file-system / FFI involvement.
class _FakeDpapiStorage implements DpapiStorage {
  final Map<String, String> _data = <String, String>{};

  /// Read-only view of the current backing store, for assertions.
  Map<String, String> get snapshot => Map<String, String>.unmodifiable(_data);

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _data.clear();
  }

  @override
  Future<bool> containsKey(String key) async => _data.containsKey(key);
}

// Storage-layout constants, mirrored from the implementation so the tests can
// assert against the on-disk shape without reaching into private members.
const String _profilePrefix = 'gitopen:auth:profile:';
const String _profileIndexKey = 'gitopen:auth:profile_index';
const String _migrationMarker = 'gitopen:auth:migrated_v1';
const String _legacyPrefix = 'gitopen:auth:';
const String _legacyIndexKey = '${_legacyPrefix}__index__';

void main() {
  late _FakeDpapiStorage storage;
  late SecureAuthProfileStore sut;

  setUp(() {
    storage = _FakeDpapiStorage();
    sut = SecureAuthProfileStore(storage: storage);
  });

  group('upsert / get', () {
    test('upsert then get round-trips the profile', () async {
      final created = await sut.upsert(
        host: 'github.com',
        username: 'alice',
        spec: const AuthHttpsPat(username: 'alice', token: 'tok-123'),
      );

      expect(created.host, 'github.com');
      expect(created.username, 'alice');
      expect(created.id, isNotEmpty);

      // AuthSpec subtypes are not Equatable, so AuthProfile equality (which
      // includes spec in its props) does not hold across re-decoded
      // instances. Assert the persisted fields individually instead.
      final fetched = await sut.get(created.id);
      expect(fetched, isNotNull);
      expect(fetched!.id, created.id);
      expect(fetched.host, 'github.com');
      expect(fetched.username, 'alice');
      final spec = fetched.spec;
      expect(spec, isA<AuthHttpsPat>());
      expect((spec as AuthHttpsPat).token, 'tok-123');
    });

    test('upsert generates a 16-char hex id when none supplied', () async {
      final created = await sut.upsert(
        host: 'github.com',
        username: 'alice',
        spec: const AuthSystemDefault(),
      );

      expect(created.id, matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('upsert with an explicit id overwrites the existing profile',
        () async {
      await sut.upsert(
        host: 'github.com',
        username: 'alice',
        spec: const AuthSystemDefault(),
        id: 'fixed-id',
      );
      final updated = await sut.upsert(
        host: 'github.com',
        username: 'alice-renamed',
        spec: const AuthSystemDefault(),
        id: 'fixed-id',
      );

      expect(updated.id, 'fixed-id');
      final fetched = await sut.get('fixed-id');
      expect(fetched?.username, 'alice-renamed');

      // The index must not gain a duplicate entry on re-upsert.
      final index =
          (jsonDecode(storage.snapshot[_profileIndexKey]!) as List<dynamic>)
              .cast<String>();
      expect(index.where((id) => id == 'fixed-id'), hasLength(1));
    });

    test('get returns null for an unknown id', () async {
      expect(await sut.get('does-not-exist'), isNull);
    });

    test('get returns null when the stored blob is corrupt', () async {
      // Seed an index entry and a profile key whose value is not valid JSON.
      await storage.write(_profileIndexKey, jsonEncode(['broken']));
      await storage.write('$_profilePrefix' 'broken', 'not-json{');

      expect(await sut.get('broken'), isNull);
    });
  });

  group('list', () {
    test('reflects upserts in insertion order', () async {
      final a = await sut.upsert(
        host: 'github.com',
        username: 'alice',
        spec: const AuthSystemDefault(),
      );
      final b = await sut.upsert(
        host: 'gitlab.com',
        username: 'bob',
        spec: const AuthSystemDefault(),
      );

      final all = await sut.list();
      expect(all.map((p) => p.id), [a.id, b.id]);
    });

    test('is empty on a fresh store', () async {
      expect(await sut.list(), isEmpty);
    });

    test('skips index entries whose profile blob is missing', () async {
      final a = await sut.upsert(
        host: 'github.com',
        username: 'alice',
        spec: const AuthSystemDefault(),
      );
      // Inject a dangling id into the index without a backing profile.
      final index =
          (jsonDecode(storage.snapshot[_profileIndexKey]!) as List<dynamic>)
              .cast<String>()
            ..add('dangling');
      await storage.write(_profileIndexKey, jsonEncode(index));

      final all = await sut.list();
      expect(all.map((p) => p.id), [a.id]);
    });
  });

  group('forHost', () {
    test('returns only profiles matching the host', () async {
      final gh1 = await sut.upsert(
        host: 'github.com',
        username: 'alice',
        spec: const AuthSystemDefault(),
      );
      final gh2 = await sut.upsert(
        host: 'github.com',
        username: 'bob',
        spec: const AuthSystemDefault(),
      );
      await sut.upsert(
        host: 'gitlab.com',
        username: 'carol',
        spec: const AuthSystemDefault(),
      );

      final matches = await sut.forHost('github.com');
      expect(matches.map((p) => p.id), unorderedEquals([gh1.id, gh2.id]));
    });

    test('returns empty for an unknown host', () async {
      await sut.upsert(
        host: 'github.com',
        username: 'alice',
        spec: const AuthSystemDefault(),
      );
      expect(await sut.forHost('example.com'), isEmpty);
    });
  });

  group('delete', () {
    test('removes the profile and its index entry', () async {
      final a = await sut.upsert(
        host: 'github.com',
        username: 'alice',
        spec: const AuthSystemDefault(),
      );
      final b = await sut.upsert(
        host: 'gitlab.com',
        username: 'bob',
        spec: const AuthSystemDefault(),
      );

      await sut.delete(a.id);

      expect(await sut.get(a.id), isNull);
      final all = await sut.list();
      expect(all.map((p) => p.id), [b.id]);
      expect(storage.snapshot.containsKey('$_profilePrefix${a.id}'), isFalse);

      final index =
          (jsonDecode(storage.snapshot[_profileIndexKey]!) as List<dynamic>)
              .cast<String>();
      expect(index, [b.id]);
    });

    test('is a no-op for an unknown id', () async {
      final a = await sut.upsert(
        host: 'github.com',
        username: 'alice',
        spec: const AuthSystemDefault(),
      );
      await sut.delete('not-there');
      expect((await sut.list()).map((p) => p.id), [a.id]);
    });
  });

  group('AuthSpec encode / decode round-trip', () {
    Future<AuthSpec?> roundTrip(AuthSpec spec) async {
      final created = await sut.upsert(
        host: 'github.com',
        username: 'u',
        spec: spec,
      );
      final fetched = await sut.get(created.id);
      return fetched?.spec;
    }

    test('AuthHttpsPat', () async {
      final decoded = await roundTrip(
        const AuthHttpsPat(username: 'alice', token: 'tok'),
      );
      expect(decoded, isA<AuthHttpsPat>());
      final pat = decoded! as AuthHttpsPat;
      expect(pat.username, 'alice');
      expect(pat.token, 'tok');
    });

    test('AuthHttpsBasic', () async {
      final decoded = await roundTrip(
        const AuthHttpsBasic(username: 'alice', password: 'hunter2'),
      );
      expect(decoded, isA<AuthHttpsBasic>());
      final basic = decoded! as AuthHttpsBasic;
      expect(basic.username, 'alice');
      expect(basic.password, 'hunter2');
    });

    test('AuthSsh with passphrase', () async {
      final decoded = await roundTrip(
        const AuthSsh(privateKeyPath: '/home/a/.ssh/id', passphrase: 'pp'),
      );
      expect(decoded, isA<AuthSsh>());
      final ssh = decoded! as AuthSsh;
      expect(ssh.privateKeyPath, '/home/a/.ssh/id');
      expect(ssh.passphrase, 'pp');
    });

    test('AuthSsh without passphrase preserves null', () async {
      final decoded = await roundTrip(
        const AuthSsh(privateKeyPath: '/home/a/.ssh/id'),
      );
      final ssh = decoded! as AuthSsh;
      expect(ssh.passphrase, isNull);
    });

    test('AuthGitHubOauth', () async {
      final decoded = await roundTrip(const AuthGitHubOauth('gho_abc'));
      expect(decoded, isA<AuthGitHubOauth>());
      expect((decoded! as AuthGitHubOauth).accessToken, 'gho_abc');
    });

    test('AuthSystemDefault', () async {
      final decoded = await roundTrip(const AuthSystemDefault());
      expect(decoded, isA<AuthSystemDefault>());
    });

    test('persisted blob carries the expected spec kind', () async {
      final created = await sut.upsert(
        host: 'github.com',
        username: 'alice',
        spec: const AuthHttpsPat(username: 'alice', token: 'tok'),
      );
      final blob = storage.snapshot['$_profilePrefix${created.id}']!;
      final json = jsonDecode(blob) as Map<String, dynamic>;
      expect(json['host'], 'github.com');
      expect((json['spec'] as Map<String, dynamic>)['kind'], 'pat');
    });
  });

  group('legacy migration', () {
    test('wraps legacy host-keyed entries into profiles', () async {
      await storage.write(
        _legacyIndexKey,
        jsonEncode(['github.com', 'gitlab.com']),
      );
      await storage.write(
        '$_legacyPrefix' 'github.com',
        jsonEncode({'kind': 'pat', 'username': 'alice', 'token': 'tok'}),
      );
      await storage.write(
        '$_legacyPrefix' 'gitlab.com',
        jsonEncode({'kind': 'ssh', 'keyPath': '/k', 'passphrase': null}),
      );

      final all = await sut.list();
      expect(all, hasLength(2));

      final byHost = {for (final p in all) p.host: p};
      expect(byHost['github.com']!.spec, isA<AuthHttpsPat>());
      expect(byHost['github.com']!.username, 'alice');
      expect(byHost['gitlab.com']!.spec, isA<AuthSsh>());
      // SSH legacy entries have no username; the store fills a placeholder.
      expect(byHost['gitlab.com']!.username, '(ssh key)');
    });

    test('sets the migration marker after a successful migration', () async {
      await storage.write(_legacyIndexKey, jsonEncode(['github.com']));
      await storage.write(
        '$_legacyPrefix' 'github.com',
        jsonEncode({'kind': 'github', 'token': 'gho_x'}),
      );

      await sut.list();
      expect(storage.snapshot[_migrationMarker], 'ok');
    });

    test('sets the marker even when there is nothing to migrate', () async {
      await sut.list();
      expect(storage.snapshot[_migrationMarker], 'ok');
    });

    test('leaves legacy keys in place after migration', () async {
      await storage.write(_legacyIndexKey, jsonEncode(['github.com']));
      await storage.write(
        '$_legacyPrefix' 'github.com',
        jsonEncode({'kind': 'github', 'token': 'gho_x'}),
      );

      await sut.list();
      expect(storage.snapshot.containsKey(_legacyIndexKey), isTrue);
      expect(
        storage.snapshot.containsKey('$_legacyPrefix' 'github.com'),
        isTrue,
      );
    });

    test('skips unparseable legacy entries but migrates the valid ones',
        () async {
      await storage.write(
        _legacyIndexKey,
        jsonEncode(['good.com', 'bad.com']),
      );
      await storage.write(
        '$_legacyPrefix' 'good.com',
        jsonEncode({'kind': 'github', 'token': 'gho_ok'}),
      );
      await storage.write('$_legacyPrefix' 'bad.com', 'not-json{');

      final all = await sut.list();
      expect(all.map((p) => p.host), ['good.com']);
      // Marker is still set so the bad entry is not retried forever.
      expect(storage.snapshot[_migrationMarker], 'ok');
    });

    test('is idempotent: a second instance does not re-migrate', () async {
      await storage.write(_legacyIndexKey, jsonEncode(['github.com']));
      await storage.write(
        '$_legacyPrefix' 'github.com',
        jsonEncode({'kind': 'github', 'token': 'gho_x'}),
      );

      final first = await sut.list();
      expect(first, hasLength(1));

      // A brand-new store sees marker == 'ok' and must not duplicate profiles.
      final fresh = SecureAuthProfileStore(storage: storage);
      final second = await fresh.list();
      expect(second.map((p) => p.id), first.map((p) => p.id).toList());

      final index =
          (jsonDecode(storage.snapshot[_profileIndexKey]!) as List<dynamic>)
              .cast<String>();
      expect(index, hasLength(1));
    });

    test('migration runs only once per instance across calls', () async {
      await storage.write(_legacyIndexKey, jsonEncode(['github.com']));
      await storage.write(
        '$_legacyPrefix' 'github.com',
        jsonEncode({'kind': 'github', 'token': 'gho_x'}),
      );

      await sut.list();
      // Manually add a second legacy entry after the first migration ran.
      await storage.write(
        _legacyIndexKey,
        jsonEncode(['github.com', 'gitlab.com']),
      );
      await storage.write(
        '$_legacyPrefix' 'gitlab.com',
        jsonEncode({'kind': 'github', 'token': 'gho_y'}),
      );

      // Same instance: marker already true in-memory, no re-migration.
      final all = await sut.list();
      expect(all.map((p) => p.host), ['github.com']);
    });
  });
}
