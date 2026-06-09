import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_spec.dart';

void main() {
  const baseSpec = AuthHttpsPat(username: 'octocat', token: 'ghp_x');
  const base = AuthProfile(
    id: 'p1',
    host: 'github.com',
    username: 'octocat',
    spec: baseSpec,
  );

  group('AuthProfile', () {
    test('label combines host and username', () {
      expect(base.label, 'github.com / octocat');
    });

    test('copyWith overrides username only, keeping id/host/spec', () {
      final updated = base.copyWith(username: 'renamed');
      expect(updated.id, 'p1');
      expect(updated.host, 'github.com');
      expect(updated.username, 'renamed');
      expect(updated.spec, same(baseSpec));
      expect(updated.label, 'github.com / renamed');
    });

    test('copyWith overrides spec only, keeping username', () {
      const newSpec = AuthSystemDefault();
      final updated = base.copyWith(spec: newSpec);
      expect(updated.username, 'octocat');
      expect(updated.spec, same(newSpec));
    });

    test('copyWith with no args returns an equal profile', () {
      expect(base.copyWith(), base);
    });

    test('equality is by id/host/username/spec', () {
      const same = AuthProfile(
        id: 'p1',
        host: 'github.com',
        username: 'octocat',
        spec: baseSpec,
      );
      const differentId = AuthProfile(
        id: 'p2',
        host: 'github.com',
        username: 'octocat',
        spec: baseSpec,
      );
      expect(base, same);
      expect(base, isNot(differentId));
      expect(base.props, ['p1', 'github.com', 'octocat', baseSpec]);
    });
  });
}
