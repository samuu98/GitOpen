import 'dart:io';

import '../../application/launcher/process_runner.dart';

class SystemProcessRunner implements ProcessRunner {
  @override
  Future<ProcessProbeResult> probe(String command) async {
    final probe = Platform.isWindows ? 'where' : 'which';
    try {
      final result = await Process.run(probe, [command], runInShell: false);
      if (result.exitCode != 0) return const ProcessProbeResult(false, null);
      final out = (result.stdout as String).trim();
      if (out.isEmpty) return const ProcessProbeResult(false, null);
      final firstLine = out.split(RegExp(r'\r?\n')).first.trim();
      return ProcessProbeResult(true, firstLine);
    } on ProcessException {
      return const ProcessProbeResult(false, null);
    }
  }

  @override
  Future<bool> startDetached(String executable, List<String> args) async {
    try {
      await Process.start(
        executable,
        args,
        mode: ProcessStartMode.detached,
        runInShell: Platform.isWindows,
      );
      return true;
    } on ProcessException {
      return false;
    }
  }
}
