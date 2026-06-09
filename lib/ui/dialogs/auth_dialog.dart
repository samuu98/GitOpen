import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/git/auth_spec.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/infrastructure/auth/github_device_flow.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';
import 'package:url_launcher/url_launcher.dart';

/// Dialog that lets the user sign in with one of three methods:
///  - HTTPS personal-access-token (username + token)
///  - SSH key (path to private key)
///  - GitHub OAuth Device Flow (for `github.com`)
///
/// On success the credential is persisted as an [AuthProfile] in the
/// [authProfileStoreProvider] and returned to the caller, so the caller
/// can bind the current repository to that profile if desired.
class AuthDialog extends ConsumerStatefulWidget {

  const AuthDialog({required this.host, super.key, this.editing});
  final String host;

  /// When non-null, the dialog edits the existing profile (same id, host)
  /// instead of creating a new one.
  final AuthProfile? editing;

  static Future<AuthProfile?> show(
    BuildContext context,
    String host, {
    AuthProfile? editing,
  }) {
    return showDialog<AuthProfile>(
      context: context,
      builder: (_) => AuthDialog(host: host, editing: editing),
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
  final _sshLabelCtl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: widget.host == 'github.com' ? 3 : 2,
      vsync: this,
    );
    final existing = widget.editing;
    if (existing != null) {
      _userCtl.text = existing.username;
      _sshLabelCtl.text = existing.username;
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _userCtl.dispose();
    _tokenCtl.dispose();
    _sshPathCtl.dispose();
    _sshLabelCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isGitHub = widget.host == 'github.com';
    final palette = AppPalette.of(context);
    return AppDialog(
      title: widget.editing != null
          ? 'Edit credential for ${widget.host}'
          : 'Add credential for ${widget.host}',
      width: 480,
      contentPadding: EdgeInsets.zero,
      busy: _busy,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TabBar(
            controller: _tabs,
            labelStyle: const TextStyle(fontSize: 12.5),
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
                _httpsTab(context),
                _sshTab(context),
                if (isGitHub)
                  _GitHubOAuthTab(
                    clientId:
                        ref.read(appSettingsProvider).githubClientId ?? '',
                    onToken: _onGitHubToken,
                  ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                _error!,
                style: TextStyle(color: palette.accentErr, fontSize: 11),
              ),
            ),
        ],
      ),
      actions: [
        AppButton.secondary(
          label: 'Cancel',
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
        AppButton.primary(
          label: 'Save',
          onPressed: _busy ? null : _onSubmit,
        ),
      ],
    );
  }

  Widget _httpsTab(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          TextField(
            controller: _userCtl,
            style: TextStyle(color: palette.fg0, fontSize: 13),
            decoration: appInputDecoration(context, label: 'Username'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenCtl,
            obscureText: true,
            style: TextStyle(color: palette.fg0, fontSize: 13),
            decoration: appInputDecoration(context,
                label: 'Personal Access Token'),
          ),
        ],
      ),
    );
  }

  Widget _sshTab(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          TextField(
            controller: _sshLabelCtl,
            style: TextStyle(color: palette.fg0, fontSize: 13),
            decoration: appInputDecoration(context,
                label: 'Account label (e.g. github username)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sshPathCtl,
            style: TextStyle(color: palette.fg0, fontSize: 13),
            decoration: appInputDecoration(
              context,
              label: 'Path to private key',
              hint: '~/.ssh/id_ed25519',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onGitHubToken(String token) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Resolve the actual GitHub username so the profile shows up labeled
      // correctly in the account switcher.  Without this two GitHub
      // accounts would both surface as the generic "(unknown)".
      final username = await _fetchGitHubUsername(token);
      final spec = AuthGitHubOauth(token);
      final profile = await _saveProfile(username: username, spec: spec);
      if (mounted) Navigator.pop(context, profile);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Sign-in succeeded but could not save profile: $e';
        });
      }
    }
  }

  Future<void> _onSubmit() async {
    if (_tabs.index == 2) return; // GitHub tab has its own submit path
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      AuthSpec spec;
      String username;
      if (_tabs.index == 0) {
        if (_userCtl.text.trim().isEmpty || _tokenCtl.text.isEmpty) {
          throw const FormatException(
            'Username and token are required.',
          );
        }
        username = _userCtl.text.trim();
        spec = AuthHttpsPat(username: username, token: _tokenCtl.text);
      } else {
        if (_sshPathCtl.text.trim().isEmpty) {
          throw const FormatException('Key path is required.');
        }
        username = _sshLabelCtl.text.trim().isEmpty
            ? '(ssh)'
            : _sshLabelCtl.text.trim();
        spec = AuthSsh(privateKeyPath: _sshPathCtl.text.trim());
      }
      final profile = await _saveProfile(username: username, spec: spec);
      if (mounted) Navigator.pop(context, profile);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is FormatException ? e.message : 'Save failed: $e';
        });
      }
    }
  }

  Future<AuthProfile> _saveProfile({
    required String username,
    required AuthSpec spec,
  }) {
    final store = ref.read(authProfileStoreProvider);
    return store.upsert(
      id: widget.editing?.id,
      host: widget.host,
      username: username,
      spec: spec,
    );
  }

  /// Calls `GET https://api.github.com/user` with the OAuth token and
  /// returns the authenticated user's `login`.  Falls back to a sentinel
  /// label on failure rather than blocking the sign-in flow.
  Future<String> _fetchGitHubUsername(String token) async {
    final login = await ref.read(gitHubUserServiceProvider).fetchLogin(token);
    return login ?? '(github user)';
  }
}

// ---------------------------------------------------------------------------
// GitHub OAuth Device Flow tab
// ---------------------------------------------------------------------------

class _GitHubOAuthTab extends StatefulWidget {
  const _GitHubOAuthTab({required this.clientId, required this.onToken});
  final String clientId;
  final Future<void> Function(String token) onToken;

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
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: _userCode ?? '')),
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
      await _openBrowser();
      final token = await flow.pollForToken(resp);
      await widget.onToken(token);
    } on Object catch (e) {
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
