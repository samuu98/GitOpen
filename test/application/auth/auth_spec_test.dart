import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auth/auth_spec.dart';

void main() {
  group('AuthSpec subtypes', () {
    test('AuthHttpsPat carries username and token', () {
      const spec = AuthHttpsPat(username: 'alice', token: 'ghp_abc');
      expect(spec.username, 'alice');
      expect(spec.token, 'ghp_abc');
      expect(spec, isA<AuthSpec>());
    });

    test('AuthHttpsBasic carries username and password', () {
      const spec = AuthHttpsBasic(username: 'bob', password: 'hunter2');
      expect(spec.username, 'bob');
      expect(spec.password, 'hunter2');
      expect(spec, isA<AuthSpec>());
    });

    test('AuthSsh carries key path and optional passphrase', () {
      const withPass =
          AuthSsh(privateKeyPath: '/home/u/.ssh/id_ed25519', passphrase: 'pw');
      expect(withPass.privateKeyPath, '/home/u/.ssh/id_ed25519');
      expect(withPass.passphrase, 'pw');

      const withoutPass = AuthSsh(privateKeyPath: '/keys/id_rsa');
      expect(withoutPass.privateKeyPath, '/keys/id_rsa');
      expect(withoutPass.passphrase, isNull);
    });

    test('AuthGitHubOauth carries access token positionally', () {
      const spec = AuthGitHubOauth('gho_token');
      expect(spec.accessToken, 'gho_token');
      expect(spec, isA<AuthSpec>());
    });

    test('AuthSystemDefault is a const sentinel', () {
      const a = AuthSystemDefault();
      const b = AuthSystemDefault();
      // const-canonicalized: identical instances.
      expect(identical(a, b), isTrue);
      expect(a, isA<AuthSpec>());
    });

    test('exhaustive switch covers every sealed subtype', () {
      String describe(AuthSpec spec) => switch (spec) {
            AuthHttpsPat() => 'pat',
            AuthHttpsBasic() => 'basic',
            AuthSsh() => 'ssh',
            AuthGitHubOauth() => 'oauth',
            AuthSystemDefault() => 'system',
          };
      expect(describe(const AuthHttpsPat(username: 'u', token: 't')), 'pat');
      expect(describe(const AuthHttpsBasic(username: 'u', password: 'p')),
          'basic');
      expect(describe(const AuthSsh(privateKeyPath: '/k')), 'ssh');
      expect(describe(const AuthGitHubOauth('tok')), 'oauth');
      expect(describe(const AuthSystemDefault()), 'system');
    });
  });
}
