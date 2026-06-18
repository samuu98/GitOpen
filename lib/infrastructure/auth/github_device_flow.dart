import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpException;

import 'package:gitopen/application/auth/device_flow_controller.dart';
import 'package:http/http.dart' as http;

/// GitHub OAuth Device Flow client.
///
/// Usage:
///   1. Call [requestDeviceCode] to get a [DeviceCodeResponse] containing
///      `userCode` and `verificationUri`.
///   2. Show `userCode` to the user and open `verificationUri` in a browser
///      (e.g. via `url_launcher`).
///   3. Call [pollForToken] in the background.  It resolves to an access
///      token string once the user completes authorisation on GitHub.
///
/// **Client ID:**
/// Register a public OAuth App at https://github.com/settings/applications/new
/// (select "OAuth Apps", NOT "GitHub Apps").  Set the callback URL to
/// `http://localhost` (unused for Device Flow).  Copy the generated
/// `client_id` and pass it to the constructor.
class GitHubDeviceFlow {

  GitHubDeviceFlow({required this.clientId, http.Client? client})
      : _client = client ?? http.Client();
  final String clientId;
  final http.Client _client;

  /// Requests a device + user code from GitHub.
  ///
  /// [scope] defaults to `'repo read:org user:email'`: repository access for
  /// fetch/push, org-repo visibility, and `user:email` so the per-folder
  /// identity resolver can match the account by its verified emails.
  Future<DeviceCodeResponse> requestDeviceCode({
    String scope = 'repo read:org user:email',
  }) async {
    if (clientId.isEmpty) {
      throw StateError('GitHub Client ID not configured. Settings → GitHub.');
    }
    final r = await _client.post(
      Uri.parse('https://github.com/login/device/code'),
      headers: {'Accept': 'application/json'},
      body: {'client_id': clientId, 'scope': scope},
    );
    if (r.statusCode != 200) {
      throw HttpException(
        'device/code returned ${r.statusCode}: ${r.body}',
        uri: Uri.parse('https://github.com/login/device/code'),
      );
    }
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return DeviceCodeResponse(
      deviceCode: m['device_code'] as String,
      userCode: m['user_code'] as String,
      verificationUri: m['verification_uri'] as String,
      expiresIn: Duration(seconds: m['expires_in'] as int),
      interval: Duration(seconds: m['interval'] as int),
    );
  }

  /// Polls GitHub until the user completes authorisation or the code expires.
  ///
  /// Returns the access token string on success.
  /// Throws [TimeoutException] if the device code expires before authorisation.
  /// Throws [StateError] for unexpected error responses from GitHub.
  ///
  /// Transient transport failures (a dropped connection, a proxy hiccup, an
  /// unparsable body) do NOT abort the poll — the user is mid-authorisation
  /// in the browser; the loop keeps retrying until the code expires. Only an
  /// explicit error response from GitHub is fatal.
  Future<String> pollForToken(DeviceCodeResponse resp) async {
    final deadline = DateTime.now().add(resp.expiresIn);
    var pollInterval = resp.interval;

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
      final Map<String, dynamic> m;
      try {
        final response = await _client.post(
          Uri.parse('https://github.com/login/oauth/access_token'),
          headers: {'Accept': 'application/json'},
          body: {
            'client_id': clientId,
            'device_code': resp.deviceCode,
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          },
        );
        m = jsonDecode(response.body) as Map<String, dynamic>;
      } on Object {
        continue; // transient — retry on the next tick
      }
      final error = m['error'] as String?;
      if (error == 'authorization_pending') continue;
      if (error == 'slow_down') {
        // GitHub requests we back off; add 5 s on top of the current interval.
        pollInterval += const Duration(seconds: 5);
        continue;
      }
      if (error != null) {
        throw StateError('GitHub Device Flow error: $error');
      }
      final token = m['access_token'];
      if (token is String) return token;
    }
    throw TimeoutException(
      'GitHub Device Flow timed out — the device code expired.',
    );
  }
}

/// Adapts [GitHubDeviceFlow] to the application's [DeviceFlowPort] so the
/// device-flow state machine can be driven without the UI touching
/// infrastructure (or tests touching HTTP).
class GitHubDeviceFlowPort implements DeviceFlowPort {
  GitHubDeviceFlowPort(this._flow);
  final GitHubDeviceFlow _flow;

  @override
  Future<DeviceFlowSession> requestDeviceCode() async {
    final resp = await _flow.requestDeviceCode();
    return _GitHubDeviceFlowSession(_flow, resp);
  }
}

class _GitHubDeviceFlowSession implements DeviceFlowSession {
  _GitHubDeviceFlowSession(this._flow, this._resp);
  final GitHubDeviceFlow _flow;
  final DeviceCodeResponse _resp;

  @override
  String get userCode => _resp.userCode;

  @override
  String get verificationUri => _resp.verificationUri;

  @override
  Future<String> pollForToken() => _flow.pollForToken(_resp);
}

/// Response from the initial device-code request.
class DeviceCodeResponse {

  const DeviceCodeResponse({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final Duration expiresIn;
  final Duration interval;
}
