import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/git/auth_spec.dart';
import '../../../application/providers.dart';
import '../../dialogs/auth_dialog.dart';
import '../../dialogs/confirm_dialog.dart';
import '../../theme/app_palette.dart';

final _hostsProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  final store = ref.watch(credentialsStoreProvider);
  return store.hosts();
});

class AuthenticationSection extends ConsumerWidget {
  const AuthenticationSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final hosts = ref.watch(_hostsProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Saved credentials', style: TextStyle(color: p.fg0, fontSize: 14, fontWeight: FontWeight.w600)),
          const Spacer(),
          ElevatedButton.icon(
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Add credential'),
            onPressed: () async {
              final host = await _promptHost(context);
              if (host == null || host.isEmpty) return;
              if (context.mounted) await AuthDialog.show(context, host);
              ref.invalidate(_hostsProvider);
            },
          ),
        ]),
        const SizedBox(height: 16),
        hosts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e', style: TextStyle(color: p.accentErr)),
          data: (hosts) => hosts.isEmpty
              ? Text('No saved credentials.', style: TextStyle(color: p.fg2))
              : Column(children: [
                  for (final host in hosts) _HostRow(host: host, ref: ref),
                ]),
        ),
      ]),
    );
  }

  Future<String?> _promptHost(BuildContext context) async {
    final ctl = TextEditingController();
    return showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('Add credential for host'),
      content: TextField(controller: ctl, decoration: const InputDecoration(hintText: 'github.com')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: () => Navigator.pop(context, ctl.text.trim()), child: const Text('Next')),
      ],
    ));
  }
}

class _HostRow extends StatelessWidget {
  final String host;
  final WidgetRef ref;
  const _HostRow({required this.host, required this.ref});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final store = ref.read(credentialsStoreProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(children: [
        Icon(Icons.key, size: 14, color: p.fg2),
        const SizedBox(width: 8),
        Expanded(child: FutureBuilder<AuthSpec?>(
          future: store.get(host),
          builder: (_, snap) {
            final kind = _kindLabel(snap.data);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(host, style: TextStyle(color: p.fg0, fontSize: 13)),
              Text(kind, style: TextStyle(color: p.fg2, fontSize: 11)),
            ]);
          },
        )),
        TextButton(
          onPressed: () async {
            await AuthDialog.show(context, host);
            ref.invalidate(_hostsProvider);
          },
          child: const Text('Edit'),
        ),
        TextButton(
          onPressed: () async {
            final ok = await ConfirmDialog.show(context,
                title: 'Delete credential', body: 'Remove saved credential for $host?',
                confirmLabel: 'Delete', dangerous: true);
            if (ok) {
              await store.delete(host);
              ref.invalidate(_hostsProvider);
            }
          },
          child: const Text('Delete'),
        ),
        TextButton(
          onPressed: () async {
            final result = await Process.run('git', ['ls-remote', 'https://$host'], runInShell: true);
            final ok = result.exitCode == 0;
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ok ? 'OK: $host reachable' : 'Failed: ${result.stderr}'),
              ));
            }
          },
          child: const Text('Test'),
        ),
      ]),
    );
  }

  String _kindLabel(AuthSpec? s) {
    if (s == null) return '(missing)';
    return switch (s) {
      AuthHttpsPat() => 'HTTPS PAT',
      AuthHttpsBasic() => 'HTTPS Basic',
      AuthSsh() => 'SSH Key',
      AuthGitHubOauth() => 'GitHub OAuth',
      AuthSystemDefault() => 'System default',
    };
  }
}
