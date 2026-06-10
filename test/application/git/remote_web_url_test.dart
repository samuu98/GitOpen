import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/remote_web_url.dart';

void main() {
  group('RemoteWebUrl.parse', () {
    test('parses https github remote', () {
      final web = RemoteWebUrl.parse('https://github.com/user/repo.git')!;
      expect(web.base, 'https://github.com/user/repo');
      expect(web.commit('abc123'), 'https://github.com/user/repo/commit/abc123');
      expect(web.branch('feature/x'),
          'https://github.com/user/repo/tree/feature/x');
    });

    test('parses scp-style ssh remote', () {
      final web = RemoteWebUrl.parse('git@github.com:user/repo.git')!;
      expect(web.base, 'https://github.com/user/repo');
    });

    test('parses ssh:// remote with port', () {
      final web = RemoteWebUrl.parse('ssh://git@github.com:22/user/repo.git')!;
      expect(web.base, 'https://github.com/user/repo');
    });

    test('parses https remote without .git suffix', () {
      final web = RemoteWebUrl.parse('https://github.com/user/repo')!;
      expect(web.base, 'https://github.com/user/repo');
    });

    test('gitlab uses /-/ paths', () {
      final web = RemoteWebUrl.parse('git@gitlab.com:group/sub/repo.git')!;
      expect(web.base, 'https://gitlab.com/group/sub/repo');
      expect(web.commit('abc'), 'https://gitlab.com/group/sub/repo/-/commit/abc');
      expect(web.branch('main'), 'https://gitlab.com/group/sub/repo/-/tree/main');
    });

    test('bitbucket uses /commits and /branch', () {
      final web = RemoteWebUrl.parse('https://bitbucket.org/team/repo.git')!;
      expect(web.commit('abc'), 'https://bitbucket.org/team/repo/commits/abc');
      expect(web.branch('dev'), 'https://bitbucket.org/team/repo/branch/dev');
    });

    test('credentials in https url are stripped', () {
      final web = RemoteWebUrl.parse('https://user@github.com/user/repo.git')!;
      expect(web.base, 'https://github.com/user/repo');
    });

    test('local paths are not web-mappable', () {
      expect(RemoteWebUrl.parse(r'C:\repos\thing'), isNull);
      expect(RemoteWebUrl.parse('/srv/git/thing.git'), isNull);
      expect(RemoteWebUrl.parse(''), isNull);
    });

    test('branch names with special characters are encoded', () {
      final web = RemoteWebUrl.parse('https://github.com/user/repo.git')!;
      expect(web.branch('fix#1'), 'https://github.com/user/repo/tree/fix%231');
    });
  });
}
