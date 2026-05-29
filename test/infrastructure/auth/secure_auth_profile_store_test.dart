import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/auth_spec.dart';
import 'package:gitopen/infrastructure/auth/secret_storage.dart';
import 'package:gitopen/infrastructure/auth/secure_auth_profile_store.dart';

/// In-memory [SecretStorage] standing in for the OS backend so the store
/// logic can be exercised on any platform.
class _FakeSecretStorage implements SecretStorage {
  final Map<String, String> _m = {};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

void main() {
  test('upsert / list / get / delete round-trip via the SecretStorage abstraction',
      () async {
    final store = SecureAuthProfileStore(storage: _FakeSecretStorage());

    final p = await store.upsert(
      host: 'github.com',
      username: 'octocat',
      spec: const AuthHttpsPat(username: 'octocat', token: 'ghp_token'),
    );

    expect((await store.list()).map((e) => e.id), [p.id]);

    final fetched = await store.get(p.id);
    expect(fetched, isNotNull);
    expect(fetched!.host, 'github.com');
    expect(fetched.username, 'octocat');
    expect((fetched.spec as AuthHttpsPat).token, 'ghp_token');

    expect(await store.forHost('github.com'), hasLength(1));
    expect(await store.forHost('gitlab.com'), isEmpty);

    await store.delete(p.id);
    expect(await store.list(), isEmpty);
    expect(await store.get(p.id), isNull);
  });

  test('a second profile on the same host is kept distinct', () async {
    final store = SecureAuthProfileStore(storage: _FakeSecretStorage());
    await store.upsert(
        host: 'github.com',
        username: 'a',
        spec: const AuthHttpsPat(username: 'a', token: 't1'));
    await store.upsert(
        host: 'github.com',
        username: 'b',
        spec: const AuthHttpsPat(username: 'b', token: 't2'));
    final all = await store.forHost('github.com');
    expect(all.map((e) => e.username).toSet(), {'a', 'b'});
  });
}
