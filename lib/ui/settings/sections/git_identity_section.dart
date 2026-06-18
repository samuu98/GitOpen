import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gitopen/application/active_workspace_provider.dart';
import 'package:gitopen/application/git_identity/git_identity.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/common/author_avatar.dart';
import 'package:gitopen/ui/dialogs/app_dialog.dart';
import 'package:gitopen/ui/settings/settings_widgets.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final _activeRepoIdentityProvider = FutureProvider.autoDispose
    .family<({String? name, String? email}), RepoLocation>(
  (ref, repo) async {
    return ref.watch(gitIdentityServiceProvider).readEffective(repo);
  },
);

class GitIdentitySection extends ConsumerWidget {
  const GitIdentitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final activeId = ref.watch(activeWorkspaceIdProvider);
    final workspaces = ref.watch(workspaceManagerProvider);
    final activeRepo = activeId == null
        ? null
        : workspaces
            .firstWhereOrNull((w) => w.location.id == activeId)
            ?.location;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsPageHeader(
            title: 'Git Identity',
            description:
                'Author name and email used for new commits. Each repository '
                'can override the global default.',
          ),
          const SettingsSectionTitle('Current repository'),
          if (activeRepo == null)
            const _NoRepoHint()
          else
            _CurrentIdentityCard(repo: activeRepo),
          const SettingsGap(),
          const SettingsSectionTitle('Saved profiles'),
          if (settings.gitIdentities.isEmpty)
            _EmptyProfiles()
          else
            SettingsCard(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (var i = 0; i < settings.gitIdentities.length; i++)
                    _ProfileTile(
                      index: i,
                      identity: settings.gitIdentities[i],
                      activeRepo: activeRepo,
                      isLast: i == settings.gitIdentities.length - 1,
                    ),
                ],
              ),
            ),
          const SettingsGap(),
          const SettingsSectionTitle('Add a new profile'),
          const _AddProfileForm(),
        ],
      ),
    );
  }
}

class _EmptyProfiles extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SettingsCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(Icons.fingerprint, size: 18, color: palette.fg3),
          const SizedBox(width: 10),
          Text(
            'No profiles yet — add one below to switch identities quickly.',
            style: TextStyle(color: palette.fg2, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _NoRepoHint extends StatelessWidget {
  const _NoRepoHint();
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SettingsCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(Icons.folder_off_outlined, size: 18, color: palette.fg3),
          const SizedBox(width: 10),
          Text(
            'Open a repository to view or change its committer identity.',
            style: TextStyle(color: palette.fg2, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _CurrentIdentityCard extends ConsumerWidget {
  const _CurrentIdentityCard({required this.repo});
  final RepoLocation repo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(_activeRepoIdentityProvider(repo));
    return SettingsCard(
      padding: const EdgeInsets.all(16),
      child: async.when(
        loading: () => const SizedBox(
          height: 36,
          child: Center(
              child: SizedBox(
                  height: 16,
                  width: 16,
                  child:
                      CircularProgressIndicator(strokeWidth: 1.5))),
        ),
        error: (e, _) => Text('Error reading config: $e',
            style: TextStyle(color: palette.accentErr)),
        data: (id) {
          final name = id.name ?? '(not set)';
          final email = id.email ?? '(not set)';
          return Row(
            children: [
              AuthorAvatar(name: name, email: email, size: 36),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                          color: palette.fg0,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(email,
                        style: TextStyle(
                            color: palette.fg2, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      'Effective values — local config overrides global.',
                      style: TextStyle(
                          color: palette.fg3, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileTile extends ConsumerWidget {
  const _ProfileTile({
    required this.index,
    required this.identity,
    required this.activeRepo,
    required this.isLast,
  });
  final int index;
  final GitIdentity identity;
  final RepoLocation? activeRepo;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(bottom: BorderSide(color: palette.border))),
      child: Row(
        children: [
          AuthorAvatar(
              name: identity.name, email: identity.email, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(identity.label,
                    style: TextStyle(
                        color: palette.fg0,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${identity.name} <${identity.email}>',
                    style: TextStyle(
                        color: palette.fg2,
                        fontSize: 11.5,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          if (activeRepo != null) ...[
            AppButton.secondary(
              label: 'Apply to repo',
              icon: Icons.check,
              onPressed: () => _apply(context, ref, activeRepo!),
            ),
            const SizedBox(width: 6),
          ],
          AppButton.danger(
            label: 'Remove',
            onPressed: () => ref
                .read(appSettingsProvider.notifier)
                .removeGitIdentity(index),
          ),
        ],
      ),
    );
  }

  Future<void> _apply(
      BuildContext context, WidgetRef ref, RepoLocation repo) async {
    final svc = ref.read(gitIdentityServiceProvider);
    try {
      await svc.setLocal(repo, identity.name, identity.email);
      ref.invalidate(_activeRepoIdentityProvider(repo));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Applied "${identity.label}" to this repo')),
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to apply: $e'),
          backgroundColor: AppPalette.of(context).accentErr,
        ),
      );
    }
  }
}

class _AddProfileForm extends ConsumerStatefulWidget {
  const _AddProfileForm();

  @override
  ConsumerState<_AddProfileForm> createState() => _AddProfileFormState();
}

class _AddProfileFormState extends ConsumerState<_AddProfileForm> {
  final _label = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field(
            label: 'Label',
            controller: _label,
            hint: 'e.g. Work',
            onChanged: () => setState(() {}),
          ),
          _Field(
            label: 'Name',
            controller: _name,
            hint: 'Full Name',
            onChanged: () => setState(() {}),
          ),
          _Field(
            label: 'Email',
            controller: _email,
            hint: 'name@example.com',
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton.primary(
              icon: Icons.add,
              label: 'Save profile',
              onPressed: _canSave() ? _save : null,
            ),
          ),
        ],
      ),
    );
  }

  bool _canSave() {
    return _label.text.trim().isNotEmpty &&
        _name.text.trim().isNotEmpty &&
        _email.text.trim().isNotEmpty;
  }

  Future<void> _save() async {
    await ref.read(appSettingsProvider.notifier).addGitIdentity(
          GitIdentity(
            label: _label.text.trim(),
            name: _name.text.trim(),
            email: _email.text.trim(),
          ),
        );
    if (!mounted) return;
    _label.clear();
    _name.clear();
    _email.clear();
    setState(() {});
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
  });
  final String label;
  final String hint;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: palette.fg1, fontSize: 12.5),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              style: TextStyle(color: palette.fg0, fontSize: 13),
              decoration:
                  appInputDecoration(context, label: '', hint: hint),
              onChanged: (_) => onChanged(),
            ),
          ),
        ],
      ),
    );
  }
}
