import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/auth_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// Shown when a git op fails because the currently-used credential does
/// not have access to the repository (e.g. "repository not found" — typical
/// GitHub response when two accounts share the same host).
///
/// Lists every saved [AuthProfile] for the host, lets the user pick one
/// (binding it to the current repo), or sign in with a fresh account that
/// gets added on the spot.
class AccountSwitcherDialog extends ConsumerStatefulWidget {

  const AccountSwitcherDialog({
    required this.host, required this.contextMessage, super.key,
    this.currentProfileId,
  });
  final String host;
  final String? currentProfileId;
  final String contextMessage;

  /// Returns the chosen [AuthProfile] (already persisted), or `null` if
  /// the user dismissed without choosing.  Caller is responsible for
  /// binding the repo to the returned profile.
  static Future<AuthProfile?> show(
    BuildContext context, {
    required String host,
    required String contextMessage,
    String? currentProfileId,
  }) {
    return showDialog<AuthProfile>(
      context: context,
      builder: (_) => AccountSwitcherDialog(
        host: host,
        currentProfileId: currentProfileId,
        contextMessage: contextMessage,
      ),
    );
  }

  @override
  ConsumerState<AccountSwitcherDialog> createState() =>
      _AccountSwitcherDialogState();
}

class _AccountSwitcherDialogState
    extends ConsumerState<AccountSwitcherDialog> {
  late Future<List<AuthProfile>> _profiles;

  @override
  void initState() {
    super.initState();
    _profiles = ref.read(authProfileStoreProvider).forHost(widget.host);
  }

  Future<void> _refresh() async {
    setState(() {
      _profiles = ref.read(authProfileStoreProvider).forHost(widget.host);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return AppDialog(
      title: 'Choose account for ${widget.host}',
      subtitle: widget.contextMessage,
      contentPadding: EdgeInsets.zero,
      content: FutureBuilder<List<AuthProfile>>(
        future: _profiles,
        builder: (_, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final profiles = snap.data!;
          if (profiles.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No saved accounts for this host yet.',
                style: TextStyle(color: p.fg2, fontSize: 12),
              ),
            );
          }
          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: profiles.length,
              itemBuilder: (_, i) {
                final profile = profiles[i];
                final current = profile.id == widget.currentProfileId;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    current
                        ? Icons.radio_button_checked
                        : Icons.account_circle_outlined,
                    size: 18,
                    color: current ? p.accentCurrent : p.fg2,
                  ),
                  title: Text(
                    profile.username,
                    style: TextStyle(color: p.fg0, fontSize: 13),
                  ),
                  subtitle: Text(
                    _kindLabel(profile),
                    style: TextStyle(color: p.fg2, fontSize: 11),
                  ),
                  onTap: () => Navigator.pop(context, profile),
                );
              },
            ),
          );
        },
      ),
      actions: [
        AppButton.secondary(
          label: 'Add account…',
          icon: Icons.person_add_alt_1,
          onPressed: _addAccount,
        ),
        AppButton.secondary(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Future<void> _addAccount() async {
    final added = await AuthDialog.show(context, widget.host);
    if (added == null) {
      await _refresh();
      return;
    }
    if (mounted) Navigator.pop(context, added);
  }

  String _kindLabel(AuthProfile p) {
    return switch (p.spec) {
      AuthHttpsPat() => 'HTTPS PAT',
      AuthHttpsBasic() => 'HTTPS Basic',
      AuthSsh() => 'SSH Key',
      AuthGitHubOauth() => 'GitHub OAuth',
      AuthSystemDefault() => 'System default',
    };
  }
}
