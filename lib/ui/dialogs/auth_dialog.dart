import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/git/auth_spec.dart';
import '../../application/providers.dart';
import '../../infrastructure/auth/github_device_flow.dart';
import '../theme/app_palette.dart';

class AuthDialog extends ConsumerStatefulWidget {
  final String host;
  const AuthDialog({super.key, required this.host});

  static Future<AuthSpec?> show(BuildContext context, String host) {
    return showDialog<AuthSpec>(
      context: context,
      builder: (_) => AuthDialog(host: host),
    );
  }

  @override
  ConsumerState<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends ConsumerState<AuthDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _userCtl = TextEditingController();
  final _tokenCtl = TextEditingController();
  final _sshPathCtl = TextEditingController();
  bool _save = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: widget.host == 'github.com' ? 3 : 2,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    _userCtl.dispose();
    _tokenCtl.dispose();
    _sshPathCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isGitHub = widget.host == 'github.com';
    final palette = AppPalette.of(context);
    return Dialog(
      backgroundColor: palette.bg1,
      child: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Authentication required for ${widget.host}',
                style: TextStyle(
                  color: palette.fg0,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TabBar(
              controller: _tabs,
              tabs: [
                const Tab(text: 'HTTPS Token'),
                const Tab(text: 'SSH Key'),
                if (isGitHub) const Tab(text: 'GitHub Login'),
              ],
            ),
            SizedBox(
              height: 240,
              child: TabBarView(
                controller: _tabs,
                children: [
                  _httpsTab(),
                  _sshTab(),
                  if (isGitHub) _GitHubOAuthTab(
                    clientId: ref.read(appSettingsProvider).githubClientId ?? '',
                    onToken: _onGitHubToken,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Checkbox(
                    value: _save,
                    onChanged: (v) => setState(() => _save = v ?? true),
                  ),
                  Text(
                    'Save for this host',
                    style: TextStyle(color: AppPalette.of(context).fg1),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _onSubmit,
                    child: const Text('Connect'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _httpsTab() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _userCtl,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenCtl,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'Personal Access Token'),
            ),
          ],
        ),
      );

  Widget _sshTab() => Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _sshPathCtl,
          decoration: const InputDecoration(
            labelText: 'Path to private key (e.g. ~/.ssh/id_ed25519)',
          ),
        ),
      );

  /// Called by [_GitHubOAuthTab] when the Device Flow completes successfully.
  Future<void> _onGitHubToken(String token) async {
    final spec = AuthGitHubOauth(token);
    if (_save) {
      await ref.read(credentialsStoreProvider).put(widget.host, spec);
    }
    if (mounted) Navigator.pop(context, spec);
  }

  Future<void> _onSubmit() async {
    // The GitHub tab handles its own submit path via [_onGitHubToken].
    if (_tabs.index == 2) return;

    AuthSpec? spec;
    if (_tabs.index == 0) {
      if (_userCtl.text.isEmpty || _tokenCtl.text.isEmpty) return;
      spec = AuthHttpsPat(username: _userCtl.text, token: _tokenCtl.text);
    } else {
      if (_sshPathCtl.text.isEmpty) return;
      spec = AuthSsh(privateKeyPath: _sshPathCtl.text);
    }
    if (_save) await ref.read(credentialsStoreProvider).put(widget.host, spec);
    if (mounted) Navigator.pop(context, spec);
  }
}

/// GitHub OAuth Device Flow tab.
///
/// Flow:
///  1. User taps "Sign in with GitHub".
///  2. We request a device code and display the [userCode].
///  3. User opens the verification URL in the browser (or we open it for them).
///  4. We poll in the background; on success we call [onToken].
class _GitHubOAuthTab extends StatefulWidget {
  final String clientId;
  final Future<void> Function(String token) onToken;
  const _GitHubOAuthTab({required this.clientId, required this.onToken});

  @override
  State<_GitHubOAuthTab> createState() => _GitHubOAuthTabState();
}

class _GitHubOAuthTabState extends State<_GitHubOAuthTab> {
  _OAuthState _state = _OAuthState.idle;
  String? _userCode;
  String? _verificationUri;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: switch (_state) {
        _OAuthState.idle => _buildIdle(),
        _OAuthState.waiting => _buildWaiting(),
        _OAuthState.polling => _buildPolling(),
        _OAuthState.error => _buildError(),
      },
    );
  }

  Widget _buildIdle() {
    return Center(
      child: ElevatedButton.icon(
        icon: const Icon(Icons.login, size: 16),
        label: const Text('Sign in with GitHub'),
        onPressed: _startDeviceFlow,
      ),
    );
  }

  Widget _buildWaiting() {
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
              _userCode ?? '',
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
              onPressed: () => Clipboard.setData(
                ClipboardData(text: _userCode ?? ''),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          icon: const Icon(Icons.open_in_browser, size: 14),
          label: const Text('Open GitHub'),
          onPressed: _openBrowser,
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

  Widget _buildError() {
    final palette = AppPalette.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.error_outline, color: palette.accentErr, size: 32),
        const SizedBox(height: 8),
        Text(
          _errorMessage ?? 'Unknown error',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.accentErr, fontSize: 12),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() {
            _state = _OAuthState.idle;
            _errorMessage = null;
          }),
          child: const Text('Try again'),
        ),
      ],
    );
  }

  Future<void> _startDeviceFlow() async {
    setState(() => _state = _OAuthState.polling);
    try {
      final flow = GitHubDeviceFlow(clientId: widget.clientId);
      final resp = await flow.requestDeviceCode();
      setState(() {
        _userCode = resp.userCode;
        _verificationUri = resp.verificationUri;
        _state = _OAuthState.waiting;
      });
      // Open the browser automatically.
      await _openBrowser();
      // Poll in the background.
      final token = await flow.pollForToken(resp);
      await widget.onToken(token);
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _OAuthState.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _openBrowser() async {
    final uri = _verificationUri;
    if (uri == null) return;
    final url = Uri.parse(uri);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}

enum _OAuthState { idle, waiting, polling, error }
