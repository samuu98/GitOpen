import 'package:gitopen/application/auth/auth_profile.dart';

/// Outcome of probing whether a credential actually authenticates.
typedef CredentialTestResult = ({bool ok, String message});

/// Validates a saved [AuthProfile]'s credential against its host, so the UI
/// never has to shell out or make HTTP calls itself.
abstract interface class CredentialTester { // ignore: one_member_abstracts
  /// Authenticates [profile] against its host and reports success + a message
  /// safe to show the user.
  Future<CredentialTestResult> test(AuthProfile profile);
}
