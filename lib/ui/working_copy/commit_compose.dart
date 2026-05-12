import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/git/commit_request.dart';
import '../../application/git/git_result.dart';
import '../../application/providers.dart';
import '../../domain/commits/commit_sha.dart';
import '../../domain/repositories/repo_location.dart';

class CommitCompose extends ConsumerStatefulWidget {
  final RepoLocation repo;
  const CommitCompose({super.key, required this.repo});
  @override
  ConsumerState<CommitCompose> createState() => _CommitComposeState();
}

class _CommitComposeState extends ConsumerState<CommitCompose> {
  final _ctl = TextEditingController();
  bool _amend = false;
  bool _signOff = false;
  bool _busy = false;
  int _lastTrigger = 0;

  @override
  Widget build(BuildContext context) {
    // React to keyboard shortcut (Ctrl+Enter) via triggerCommitProvider.
    final triggerCount = ref.watch(triggerCommitProvider);
    if (triggerCount != _lastTrigger) {
      _lastTrigger = triggerCount;
      // Schedule the commit after the current build frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _commit();
      });
    }
    return Container(
      color: const Color(0xFF25252A),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _ctl,
          maxLines: 4, minLines: 2,
          decoration: const InputDecoration(hintText: 'Commit message', filled: true, fillColor: Color(0xFF1F1F23)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Checkbox(value: _amend, onChanged: (v) => setState(() => _amend = v ?? false)),
          const Text('Amend last commit', style: TextStyle(color: Color(0xFFB8B8BC), fontSize: 12)),
          const SizedBox(width: 16),
          Checkbox(value: _signOff, onChanged: (v) => setState(() => _signOff = v ?? false)),
          const Text('Sign off', style: TextStyle(color: Color(0xFFB8B8BC), fontSize: 12)),
          const Spacer(),
          ElevatedButton(onPressed: _busy ? null : _commit, child: const Text('Commit')),
        ]),
      ]),
    );
  }

  Future<void> _commit() async {
    if (_ctl.text.trim().isEmpty && !_amend) return;
    setState(() => _busy = true);
    final res = await ref.read(gitWriteOperationsProvider).commit(
      widget.repo,
      CommitRequest(message: _ctl.text.trim(), amend: _amend, signOff: _signOff),
    );
    setState(() => _busy = false);
    if (res is GitSuccess) {
      _ctl.clear();
      setState(() { _amend = false; _signOff = false; });
      ref.invalidate(gitReadOperationsProvider); // forces refresh
    } else if (res is GitFailure<CommitSha>) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Commit failed: ${res.message}')));
      }
    }
  }
}
