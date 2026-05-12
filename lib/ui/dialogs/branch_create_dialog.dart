import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../domain/commits/commit_sha.dart';
import '../../domain/repositories/repo_location.dart';

class BranchCreateDialog extends ConsumerStatefulWidget {
  final RepoLocation repo;
  final CommitSha? at;
  const BranchCreateDialog({super.key, required this.repo, this.at});

  static Future<bool> show(BuildContext context, RepoLocation r, {CommitSha? at}) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => BranchCreateDialog(repo: r, at: at));
    return ok ?? false;
  }

  @override
  ConsumerState<BranchCreateDialog> createState() => _State();
}

class _State extends ConsumerState<BranchCreateDialog> {
  final _ctl = TextEditingController();
  bool _checkout = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New branch'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _ctl, autofocus: true, decoration: const InputDecoration(labelText: 'Branch name')),
        const SizedBox(height: 8),
        if (widget.at != null) Text('From: ${widget.at!.short()}', style: const TextStyle(color: Color(0xFF888892))),
        Row(children: [
          Checkbox(value: _checkout, onChanged: (v) => setState(() => _checkout = v ?? true)),
          const Text('Switch to this branch'),
        ]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: _create, child: const Text('Create')),
      ],
    );
  }

  Future<void> _create() async {
    if (_ctl.text.trim().isEmpty) return;
    final write = ref.read(gitWriteOperationsProvider);
    await write.createBranch(widget.repo, _ctl.text.trim(), at: widget.at, checkout: _checkout);
    if (mounted) Navigator.pop(context, true);
  }
}
