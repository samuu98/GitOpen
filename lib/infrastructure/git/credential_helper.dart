import 'dart:convert';

import 'package:gitopen/application/auth/auth_spec.dart';

/// Produces the environment variables and extra `-c` arguments needed to make
/// a git subprocess authenticate without an interactive prompt.
///
/// For HTTPS-based credentials (PAT / Basic / GitHub OAuth) it returns an
/// `http.<remote>.extraheader` `-c` override carrying a Basic `Authorization`
/// header. This works for `git push / fetch / pull / clone` against any host
/// that honours standard HTTP Basic auth (GitHub, GitLab, Bitbucket, Gitea, …)
/// and avoids the OS credential helper entirely.
///
/// The header is **scoped to the remote's origin** (`http.https://host/…`)
/// rather than set globally. Git-lfs inherits `-c` overrides (via
/// `GIT_CONFIG_PARAMETERS`) and applies a *global* `http.extraheader` to every
/// request it makes — including the object upload to GitHub's LFS storage
/// backend (`github-cloud.s3.amazonaws.com`), whose pre-signed URL carries its
/// own auth in the query string. That host rejects the extra `Authorization`
/// header with `501 Not Implemented`, breaking every LFS push. Scoping the
/// header to the git host keeps auth working for the remote and the LFS batch
/// API (both on that host) while leaving the S3 transfer header-free. This is
/// the same fix `actions/checkout` uses (`http.https://github.com/.extraheader`).
///
/// For SSH it sets `GIT_SSH_COMMAND` with the chosen private key.
class CredentialHelper {
  /// Returns `({env, extraArgs, dispose})`:
  /// - `env` is merged into the subprocess environment
  /// - `extraArgs` are prepended to the git argv (`-c key=value` pairs)
  /// - `dispose` releases any temp resources; safe to call multiple times
  ///
  /// [remoteUrl] is the URL git will actually contact; its scheme+host scope
  /// the injected header. When null/unparseable the header falls back to the
  /// global `http.extraheader` — auth still works, but LFS pushes to that
  /// remote would hit the S3 header-leak described above.
  static Future<
      ({
        Map<String, String> env,
        List<String> extraArgs,
        void Function() dispose,
      })> setup(AuthSpec? auth, {String? remoteUrl}) async {
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
    // Scope the header to the remote's origin when we know it; otherwise fall
    // back to the global key (see the class doc for the LFS/S3 rationale).
    final scope = _scopeFromUrl(remoteUrl);
    final headerKey =
        scope == null ? 'http.extraheader' : 'http.$scope.extraheader';
    final extra = <String>[
      // Reset any inherited credential helpers (e.g. GCM on Windows) so the
      // extraheader is the only credential source git sees.
      '-c', 'credential.helper=',
      '-c', '$headerKey=Authorization: Basic $basic',
      // Refuse to fall back to the terminal prompt — surface a real error
      // instead of hanging waiting for stdin.
    ];
    return (
      env: {'GIT_TERMINAL_PROMPT': '0'},
      extraArgs: extra,
      dispose: () {},
    );
  }

  /// The `scheme://host[:port]/` prefix used to scope an `http.<url>.extraheader`
  /// config key to [remoteUrl]'s origin, or null when [remoteUrl] is absent or
  /// not an http(s) URL (e.g. an SSH remote, which never reaches this path).
  static String? _scopeFromUrl(String? remoteUrl) {
    if (remoteUrl == null) return null;
    final uri = Uri.tryParse(remoteUrl);
    if (uri == null) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    if (uri.host.isEmpty) return null;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port/';
  }
}

/// Redacts the secret in an
/// `http.[<url>.]extraheader=Authorization: <scheme> <secret>` git `-c`
/// argument so the credential never reaches logs or error messages. Returns
/// [arg] unchanged when it carries no Authorization header. Matches both the
/// global (`http.extraheader=…`) and host-scoped (`http.https://host/.extra…`)
/// key forms.
String redactExtraheaderArg(String arg) {
  const marker = 'extraheader=Authorization:';
  final i = arg.indexOf(marker);
  if (i < 0) return arg;
  return '${arg.substring(0, i + marker.length)} <redacted>';
}
