import 'dart:io';

import 'package:gitopen/application/auth/credential_tester.dart';

/// [CredentialTester] backed by an anonymous `git ls-remote https://<host>`.
class GitCredentialTester implements CredentialTester {
  const GitCredentialTester();

  @override
  Future<CredentialTestResult> test(String host) async {
    final r = await Process.run(
      'git',
      ['ls-remote', 'https://$host'],
      runInShell: true,
    );
    final ok = r.exitCode == 0;
    return (
      ok: ok,
      message: ok ? 'OK: $host reachable' : 'Failed: ${r.stderr}',
    );
  }
}
