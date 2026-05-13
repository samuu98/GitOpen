import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/active_workspace_provider.dart';
import '../../../application/git_identity/git_identity.dart';
import '../../../application/providers.dart';
import '../../../domain/repositories/repo_location.dart';
import '../../theme/app_palette.dart';

final _activeRepoIdentityProvider = FutureProvider.autoDispose
    .family<({String? name, String? email}), RepoLocation>((ref, repo) async {
  return ref.watch(gitIdentityServiceProvider).readEffective(repo);
});

class GitIdentitySection extends ConsumerWidget {
  const GitIdentitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final activeId = ref.watch(activeWorkspaceIdProvider);
    final workspaces = ref.watch(workspaceManagerProvider);
    final activeRepo = activeId == null
        ? null
        : workspaces.firstWhereOrNull((w) => w.location.id == activeId)?.location;
    final p = AppPalette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header('Current repository'),
          if (activeRepo == null)
            _NoRepoHint()
          else
            _CurrentIdentityCard(repo: activeRepo),
          const SizedBox(height: 24),
          _Header('Saved profiles'),
          if (settings.gitIdentities.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'No profiles yet. Add one below to switch identities quickly.',
                style: TextStyle(color: p.fg2, fontStyle: FontStyle.italic),
              ),
            )
          else
            for (var i = 0; i < settings.gitIdentities.length; i++)
              _ProfileTile(
                index: i,
                identity: settings.gitIdentities[i],
                activeRepo: activeRepo,
              ),
          const SizedBox(height: 24),
          _Header('Add a new profile'),
          const _AddProfileForm(),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: p.fg2,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _NoRepoHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        'Open a repository to view or change its committer identity.',
        style: TextStyle(color: p.fg2, fontStyle: FontStyle.italic),
      ),
    );
  }
}

class _CurrentIdentityCard extends ConsumerWidget {
  final RepoLocation repo;
  const _CurrentIdentityCard({required this.repo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final async = ref.watch(_activeRepoIdentityProvider(repo));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.bg2,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: async.when(
        loading: () => const SizedBox(
            height: 36,
            child: Center(
                child: SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.5)))),
        error: (e, _) => Text('Error reading config: $e',
            style: TextStyle(color: p.accentErr)),
        data: (id) {
          final name = id.name ?? '(not set)';
          final email = id.email ?? '(not set)';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                SizedBox(
                    width: 60,
                    child: Text('Name',
                        style: TextStyle(color: p.fg2, fontSize: 12))),
                Text(name, style: TextStyle(color: p.fg0, fontSize: 13)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                SizedBox(
                    width: 60,
                    child: Text('Email',
                        style: TextStyle(color: p.fg2, fontSize: 12))),
                Text(email, style: TextStyle(color: p.fg0, fontSize: 13)),
              ]),
              const SizedBox(height: 4),
              Text(
                'Effective values for this repo (local config overrides global).',
                style: TextStyle(color: p.fg3, fontSize: 11),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileTile extends ConsumerWidget {
  final int index;
  final GitIdentity identity;
  final RepoLocation? activeRepo;
  const _ProfileTile({
    required this.index,
    required this.identity,
    required this.activeRepo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: p.bg2,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(identity.label,
                    style: TextStyle(
                        color: p.fg0,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${identity.name} <${identity.email}>',
                    style: TextStyle(
                        color: p.fg2,
                        fontSize: 12,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          if (activeRepo != null)
            TextButton.icon(
              icon: const Icon(Icons.check, size: 14),
              label: const Text('Apply to repo'),
              onPressed: () => _apply(context, ref, activeRepo!),
            ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 16, color: p.fg2),
            tooltip: 'Remove profile',
            onPressed: () =>
                ref.read(appSettingsProvider.notifier).removeGitIdentity(index),
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
    } catch (e) {
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
    final p = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.bg2,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field(
              label: 'Label',
              controller: _label,
              hint: 'e.g. Work',
              onChanged: () => setState(() {})),
          _Field(
              label: 'Name',
              controller: _name,
              hint: 'Full Name',
              onChanged: () => setState(() {})),
          _Field(
              label: 'Email',
              controller: _email,
              hint: 'name@example.com',
              onChanged: () => setState(() {})),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Save profile'),
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
  final String label;
  final String hint;
  final TextEditingController controller;
  final VoidCallback onChanged;
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(color: p.fg1, fontSize: 12.5)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: hint,
                isDense: true,
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
        ],
      ),
    );
  }
}
