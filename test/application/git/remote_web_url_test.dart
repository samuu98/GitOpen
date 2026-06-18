import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/remote_web_url.dart';

void main() {
  test('normalizes git remote URLs to a browsable https URL', () {
    expect(remoteWebUrl('git@github.com:owner/repo.git'),
        'https://github.com/owner/repo');
    expect(remoteWebUrl('ssh://git@github.com/owner/repo.git'),
        'https://github.com/owner/repo');
    expect(remoteWebUrl('https://github.com/owner/repo.git'),
        'https://github.com/owner/repo');
    expect(remoteWebUrl('https://github.com/owner/repo'),
        'https://github.com/owner/repo');
    expect(remoteWebUrl('/local/path/repo.git'), isNull);
    expect(remoteWebUrl(''), isNull);
  });
}
