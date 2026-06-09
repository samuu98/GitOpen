import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/auth/device_flow_controller.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:url_launcher/url_launcher.dart';

/// The "GitHub Login" tab of the auth dialog: a thin view over the
/// application-layer [DeviceFlowController]. The widget renders the current
/// state, opens the browser when the user code is ready, and reports the
/// access token to the dialog via [onToken]; all sequencing lives in the
/// controller.
class GitHubOAuthTab extends ConsumerStatefulWidget {
  const GitHubOAuthTab({
    required this.clientId,
    required this.onToken,
    super.key,
  });
  final String clientId;
  final Future<void> Function(String token) onToken;

  @override
  ConsumerState<GitHubOAuthTab> createState() => _GitHubOAuthTabState();
}

class _GitHubOAuthTabState extends ConsumerState<GitHubOAuthTab> {
  late final DeviceFlowController _controller;
  StreamSubscription<DeviceFlowState>? _sub;

  @override
  void initState() {
    super.initState();
    _controller = DeviceFlowController(
      ref.read(deviceFlowPortProvider)(widget.clientId),
    );
    _sub = _controller.states.listen(_onState);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    // Drops any in-flight poll result so a token arriving after the dialog
    // closed can't fire callbacks on a dead widget.
    _controller.cancel();
    super.dispose();
  }

  void _onState(DeviceFlowState s) {
    setState(() {});
    switch (s) {
      case DeviceFlowAwaitingAuthorization(:final verificationUri):
        unawaited(_openBrowser(verificationUri));
      case DeviceFlowSucceeded(:final token):
        unawaited(widget.onToken(token));
      case DeviceFlowIdle():
      case DeviceFlowRequestingCode():
      case DeviceFlowFailed():
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: switch (_controller.state) {
        DeviceFlowIdle() => _buildIdle(),
        DeviceFlowAwaitingAuthorization(:final userCode) =>
          _buildWaiting(userCode),
        // While the code is being requested — and after success, while the
        // dialog saves the profile — show the plain spinner.
        DeviceFlowRequestingCode() ||
        DeviceFlowSucceeded() =>
          _buildPolling(),
        DeviceFlowFailed(:final message) => _buildError(message),
      },
    );
  }

  Widget _buildIdle() {
    return Center(
      child: ElevatedButton.icon(
        icon: const Icon(Icons.login, size: 16),
        label: const Text('Sign in with GitHub'),
        onPressed: () => unawaited(_controller.start()),
      ),
    );
  }

  Widget _buildWaiting(String userCode) {
    final palette = AppPalette.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Enter this code on GitHub:',
          style: TextStyle(color: palette.fg1, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SelectableText(
              userCode,
              style: TextStyle(
                color: palette.fg0,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 4,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.copy, size: 16, color: palette.fg2),
              tooltip: 'Copy code',
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: userCode)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          icon: const Icon(Icons.open_in_browser, size: 14),
          label: const Text('Open GitHub'),
          onPressed: () {
            if (_controller.state
                case DeviceFlowAwaitingAuthorization(:final verificationUri)) {
              unawaited(_openBrowser(verificationUri));
            }
          },
        ),
        const SizedBox(height: 8),
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(height: 6),
        Text(
          'Waiting for authorisation…',
          style: TextStyle(color: palette.fg2, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildPolling() {
    final palette = AppPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            'Waiting for GitHub authorisation…',
            style: TextStyle(color: palette.fg1, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    final palette = AppPalette.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, color: palette.accentErr, size: 32),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.accentErr, fontSize: 12),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _controller.reset,
          child: const Text('Try again'),
        ),
      ],
    );
  }

  Future<void> _openBrowser(String uri) async {
    final url = Uri.parse(uri);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
