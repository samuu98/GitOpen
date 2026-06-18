import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/auth/account_emails.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/auth_dialog.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/settings/settings_widgets.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final _profilesProvider =
    FutureProvider.autoDispose<List<AuthProfile>>((ref) async {
  // Watching the binding map ensures the list refreshes when a binding
  // change indirectly mutates settings; the store itself is the source
  // of truth for the profile list.
  ref.watch(appSettingsProvider.select((s) => s.authRepoBindings));
  return ref.read(authProfileStoreProvider).list();
});

class AuthenticationSection extends ConsumerWidget {
  const AuthenticationSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profiles = ref.watch(_profilesProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsPageHeader(
            title: 'Authentication',
            description:
                'Saved credentials for git hosts. Used automatically when '
                'fetching or pushing.',
          ),
          Row(
            children: [
              const SettingsSectionTitle('Saved accounts'),
              const Spacer(),
              AppButton.primary(
                icon: Icons.person_add_alt_1,
                label: 'Add account',
                onPressed: () async {
                  final host = await _promptHost(context);
                  if (host == null || host.isEmpty) return;
                  if (context.mounted) {
                    await AuthDialog.show(context, host);
                  }
                  ref.invalidate(_profilesProvider);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          profiles.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: $e',
                  style: TextStyle(color: palette.accentErr)),
            ),
            data: (list) => list.isEmpty
                ? _EmptyState()
                : SettingsCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        for (var i = 0; i < list.length; i++)
                          _ProfileRow(
                            profile: list[i],
                            isLast: i == list.length - 1,
                            refreshKey: ref,
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptHost(BuildContext context) async {
    final ctl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final palette = AppPalette.of(ctx);
        return AppDialog(
          title: 'Add account for host',
          width: 420,
          content: TextField(
            controller: ctl,
            autofocus: true,
            style: TextStyle(color: palette.fg0, fontSize: 13),
            decoration: appInputDecoration(
              ctx,
              label: 'Host',
              hint: 'github.com',
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            AppButton.secondary(
              label: 'Cancel',
              onPressed: () => Navigator.pop(ctx),
            ),
            AppButton.primary(
              label: 'Next',
              onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SettingsCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(Icons.lock_open_outlined, size: 18, color: palette.fg3),
          const SizedBox(width: 10),
          Text('No saved accounts yet.',
              style: TextStyle(color: palette.fg2, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {

  const _ProfileRow({
    required this.profile,
    required this.isLast,
    required this.refreshKey,
  });
  final AuthProfile profile;
  final bool isLast;
  final WidgetRef refreshKey;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final emailSuffix =
        profile.emails.isEmpty ? '' : ' · ${profile.emails.length} email(s)';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.bg3,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.border),
            ),
            child: Icon(Icons.account_circle_outlined,
                size: 18, color: palette.fg1),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  profile.username,
                  style: TextStyle(
                      color: palette.fg0,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${profile.host} · ${_kindLabel(profile.spec)}$emailSuffix',
                  style: TextStyle(color: palette.fg2, fontSize: 11.5),
                ),
              ],
            ),
          ),
          AppButton.secondary(
            label: 'Emails…',
            onPressed: () async {
              await _EmailsDialog.show(context, profile);
              refreshKey.invalidate(_profilesProvider);
            },
          ),
          const SizedBox(width: 6),
          AppButton.secondary(
            label: 'Test',
            onPressed: () async {
              final result = await refreshKey
                  .read(credentialTesterProvider)
                  .test(profile);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(result.message)),
                );
              }
            },
          ),
          const SizedBox(width: 6),
          AppButton.secondary(
            label: 'Edit',
            onPressed: () async {
              await AuthDialog.show(context, profile.host,
                  editing: profile);
              refreshKey.invalidate(_profilesProvider);
            },
          ),
          const SizedBox(width: 6),
          AppButton.danger(
            label: 'Delete',
            onPressed: () async {
              final ok = await ConfirmDialog.show(
                context,
                title: 'Delete account',
                body: 'Remove saved account ${profile.username} '
                    '(${profile.host})?',
                confirmLabel: 'Delete',
                dangerous: true,
              );
              if (!ok) return;
              await refreshKey
                  .read(authProfileStoreProvider)
                  .delete(profile.id);
              final notifier = refreshKey
                  .read(appSettingsProvider.notifier);
              final current = refreshKey
                  .read(appSettingsProvider)
                  .authRepoBindings
                  .entries
                  .where((e) => e.value == profile.id)
                  .map((e) => e.key)
                  .toList();
              for (final repoId in current) {
                await notifier.setAuthBinding(repoId, null);
              }
              refreshKey.invalidate(_profilesProvider);
            },
          ),
        ],
      ),
    );
  }

  String _kindLabel(AuthSpec s) {
    return switch (s) {
      AuthHttpsPat() => 'HTTPS PAT',
      AuthHttpsBasic() => 'HTTPS Basic',
      AuthSsh() => 'SSH Key',
      AuthGitHubOauth() => 'GitHub OAuth',
      AuthSystemDefault() => 'System default',
    };
  }
}

/// Manage the emails associated with an account: list + remove, add by hand,
/// or refresh from the GitHub API. Persists via the store on Save.
class _EmailsDialog extends ConsumerStatefulWidget {
  const _EmailsDialog({required this.profile});
  final AuthProfile profile;

  static Future<void> show(BuildContext context, AuthProfile profile) {
    return showDialog<void>(
      context: context,
      builder: (_) => _EmailsDialog(profile: profile),
    );
  }

  @override
  ConsumerState<_EmailsDialog> createState() => _EmailsDialogState();
}

class _EmailsDialogState extends ConsumerState<_EmailsDialog> {
  late final Set<String> _emails = {...widget.profile.emails};
  final _addCtl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _addCtl.dispose();
    super.dispose();
  }

  void _add() {
    final e = _addCtl.text.trim().toLowerCase();
    if (e.isEmpty) return;
    setState(() {
      _emails.add(e);
      _addCtl.clear();
    });
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final fetched = await populatedEmails(
      host: widget.profile.host,
      spec: widget.profile.spec,
      current: _emails,
      fetch: (token) async =>
          (await ref.read(gitHubUserServiceProvider).fetchAccount(token))
              .emails,
    );
    if (!mounted) return;
    setState(() {
      _emails
        ..clear()
        ..addAll(fetched);
      _busy = false;
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await ref.read(authProfileStoreProvider).upsert(
          id: widget.profile.id,
          host: widget.profile.host,
          username: widget.profile.username,
          spec: widget.profile.spec,
          emails: _emails,
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final canRefresh = githubApiToken(widget.profile.spec) != null &&
        widget.profile.host == 'github.com';
    return AppDialog(
      title: 'Emails for ${widget.profile.username}',
      subtitle: 'Used to auto-select this account for repos whose git '
          'user.email matches.',
      busy: _busy,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_emails.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No emails yet.',
                  style: TextStyle(color: palette.fg2, fontSize: 12)),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in _emails)
                  Chip(
                    label: Text(e, style: const TextStyle(fontSize: 11.5)),
                    onDeleted: () => setState(() => _emails.remove(e)),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _addCtl,
                  style: TextStyle(color: palette.fg0, fontSize: 13),
                  decoration: appInputDecoration(context, label: 'Add email'),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              AppButton.secondary(label: 'Add', onPressed: _add),
            ],
          ),
        ],
      ),
      actions: [
        if (canRefresh)
          AppButton.secondary(
            label: 'Refresh from GitHub',
            onPressed: _busy ? null : _refresh,
          ),
        AppButton.secondary(
          label: 'Cancel',
          onPressed: _busy ? null : () => Navigator.pop(context),
        ),
        AppButton.primary(label: 'Save', onPressed: _busy ? null : _save),
      ],
    );
  }
}
