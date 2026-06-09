import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/git/auth_spec.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/github_oauth_tab.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

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
                  GitHubOAuthTab(
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
