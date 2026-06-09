/// Outcome of probing whether a git host is reachable with the credential.
typedef CredentialTestResult = ({bool ok, String message});

/// Tests connectivity for a git host, so the UI never has to shell out to
/// `git` itself (keeps `dart:io` out of the widget layer).
abstract interface class CredentialTester { // ignore: one_member_abstracts
  /// Probes [host] (e.g. `github.com`) and reports success + a message.
  Future<CredentialTestResult> test(String host);
}
