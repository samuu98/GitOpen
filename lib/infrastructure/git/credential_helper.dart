import 'dart:convert';

import 'package:gitopen/application/auth/auth_spec.dart';

/// Produces the environment variables and extra `-c` arguments needed to make
/// a git subprocess authenticate without an interactive prompt.
///
/// For HTTPS-based credentials (PAT / Basic / GitHub OAuth) it returns an
/// `http.extraheader` `-c` override carrying a Basic `Authorization` header.
/// This works for `git push / fetch / pull / clone` against any host that
/// honours standard HTTP Basic auth (GitHub, GitLab, Bitbucket, Gitea, …)
/// and avoids the OS credential helper entirely.
///
/// For SSH it sets `GIT_SSH_COMMAND` with the chosen private key.
class CredentialHelper {
  /// Returns `({env, extraArgs, dispose})`:
  /// - `env` is merged into the subprocess environment
  /// - `extraArgs` are prepended to the git argv (`-c key=value` pairs)
  /// - `dispose` releases any temp resources; safe to call multiple times
  static Future<
      ({
        Map<String, String> env,
        List<String> extraArgs,
        void Function() dispose,
      })> setup(AuthSpec? auth) async {
    if (auth == null || auth is AuthSystemDefault) {
      return (
        env: <String, String>{},
        extraArgs: const <String>[],
        dispose: () {},
      );
    }

    if (auth is AuthSsh) {
      return (
        env: {
          'GIT_SSH_COMMAND':
              'ssh -i ${auth.privateKeyPath} -F /dev/null -o IdentitiesOnly=yes',
        },
        extraArgs: const <String>[],
        dispose: () {},
      );
    }

    String? username;
    String? secret;
    if (auth is AuthHttpsPat) {
      username = auth.username;
      secret = auth.token;
    } else if (auth is AuthHttpsBasic) {
      username = auth.username;
      secret = auth.password;
    } else if (auth is AuthGitHubOauth) {
      username = 'x-access-token';
      secret = auth.accessToken;
    }

    if (username == null || secret == null) {
      return (
        env: <String, String>{},
        extraArgs: const <String>[],
        dispose: () {},
      );
    }

    final basic = base64.encode(utf8.encode('$username:$secret'));
    final extra = <String>[
      // Reset any inherited credential helpers (e.g. GCM on Windows) so the
      // extraheader is the only credential source git sees.
      '-c', 'credential.helper=',
      '-c', 'http.extraheader=Authorization: Basic $basic',
      // Refuse to fall back to the terminal prompt — surface a real error
      // instead of hanging waiting for stdin.
    ];
    return (
      env: {'GIT_TERMINAL_PROMPT': '0'},
      extraArgs: extra,
      dispose: () {},
    );
  }
}
