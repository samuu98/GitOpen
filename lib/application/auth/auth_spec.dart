import 'package:equatable/equatable.dart';

/// How a git operation authenticates against a remote. Value-equal so specs
/// can be compared/deduplicated (e.g. when deciding whether a retry actually
/// changes the credential).
sealed class AuthSpec extends Equatable {
  const AuthSpec();

  @override
  List<Object?> get props => const [];
}

final class AuthHttpsPat extends AuthSpec {
  const AuthHttpsPat({required this.username, required this.token});
  final String username;
  final String token;

  @override
  List<Object?> get props => [username, token];
}

final class AuthHttpsBasic extends AuthSpec {
  const AuthHttpsBasic({required this.username, required this.password});
  final String username;
  final String password;

  @override
  List<Object?> get props => [username, password];
}

final class AuthSsh extends AuthSpec {
  const AuthSsh({required this.privateKeyPath, this.passphrase});
  final String privateKeyPath;
  final String? passphrase;

  @override
  List<Object?> get props => [privateKeyPath, passphrase];
}

final class AuthGitHubOauth extends AuthSpec {
  const AuthGitHubOauth(this.accessToken);
  final String accessToken;

  @override
  List<Object?> get props => [accessToken];
}

final class AuthSystemDefault extends AuthSpec {
  const AuthSystemDefault();
}
