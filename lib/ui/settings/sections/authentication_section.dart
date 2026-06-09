import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/git/auth_spec.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/dialogs/auth_dialog.dart';
import 'package:gitopen/ui/dialogs/confirm_dialog.dart';
import 'package:gitopen/ui/settings/settings_widgets.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final AutoDisposeFutureProvider<List<AuthProfile>> _profilesProvider =
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
                  '${profile.host} · ${_kindLabel(profile.spec)}',
                  style: TextStyle(color: palette.fg2, fontSize: 11.5),
                ),
              ],
            ),
          ),
          AppButton.secondary(
            label: 'Test',
            onPressed: () async {
              final result = await refreshKey
                  .read(credentialTesterProvider)
                  .test(profile.host);
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
