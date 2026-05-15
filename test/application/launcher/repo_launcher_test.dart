import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/launcher/process_runner.dart';
import 'package:gitopen/application/launcher/repo_launcher.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/launcher/system_repo_launcher.dart';

class FakeProcessRunner implements ProcessRunner {
  final Map<String, ProcessProbeResult> probes;
  final List<(String exe, List<String> args)> calls = [];
  final Set<String> failingExecutables;
  FakeProcessRunner({
    this.probes = const {},
    this.failingExecutables = const {},
  });

  @override
  Future<ProcessProbeResult> probe(String command) async =>
      probes[command] ?? const ProcessProbeResult(false, null);

  @override
  Future<bool> startDetached(String executable, List<String> args) async {
    calls.add((executable, args));
    return !failingExecutables.contains(executable);
  }
}

class CountingRunner implements ProcessRunner {
  int probeCount = 0;
  @override
  Future<ProcessProbeResult> probe(String command) async {
    probeCount++;
    return const ProcessProbeResult(false, null);
  }

  @override
  Future<bool> startDetached(String executable, List<String> args) async =>
      true;
}

RepoLocation _repo(String path) =>
    RepoLocation(const RepoId('id'), path, 'repo');

void main() {
  group('EditorTarget', () {
    test('equality is by id', () {
      const a = EditorTarget(
          id: 'vscode', displayName: 'VS Code', executable: 'code');
      const b = EditorTarget(
          id: 'vscode',
          displayName: 'VS Code',
          executable: '/usr/local/bin/code');
      expect(a, equals(b));
    });

    test('toString shows displayName', () {
      const e = EditorTarget(
          id: 'cursor', displayName: 'Cursor', executable: 'cursor');
      expect(e.toString(), contains('Cursor'));
    });
  });

  group('SystemRepoLauncher.revealInFiles', () {
    test('uses platform-correct command (windows)', () async {
      final fake = FakeProcessRunner();
      final launcher =
          SystemRepoLauncher(runner: fake, platformOverride: 'windows');
      await launcher.revealInFiles(_repo(r'C:\repo'));
      expect(fake.calls.single.$1, 'explorer.exe');
      expect(fake.calls.single.$2, [r'C:\repo']);
    });

    test('throws LauncherException when spawn fails', () async {
      final fake = FakeProcessRunner(failingExecutables: {'explorer.exe'});
      final launcher =
          SystemRepoLauncher(runner: fake, platformOverride: 'windows');
      expect(
        () => launcher.revealInFiles(_repo(r'C:\repo')),
        throwsA(isA<LauncherException>()),
      );
    });

    test('macOS uses open', () async {
      final fake = FakeProcessRunner();
      final launcher =
          SystemRepoLauncher(runner: fake, platformOverride: 'macos');
      await launcher.revealInFiles(_repo('/repo'));
      expect(fake.calls.single.$1, 'open');
    });

    test('linux uses xdg-open', () async {
      final fake = FakeProcessRunner();
      final launcher =
          SystemRepoLauncher(runner: fake, platformOverride: 'linux');
      await launcher.revealInFiles(_repo('/repo'));
      expect(fake.calls.single.$1, 'xdg-open');
    });
  });

  group('SystemRepoLauncher.openInTerminal', () {
    test('windows prefers wt.exe', () async {
      final fake = FakeProcessRunner();
      final launcher =
          SystemRepoLauncher(runner: fake, platformOverride: 'windows');
      await launcher.openInTerminal(_repo(r'C:\repo'));
      expect(fake.calls.single.$1, 'wt.exe');
      expect(fake.calls.single.$2, ['-d', r'C:\repo']);
    });

    test('windows falls back to powershell when wt.exe fails', () async {
      final fake = FakeProcessRunner(failingExecutables: {'wt.exe'});
      final launcher =
          SystemRepoLauncher(runner: fake, platformOverride: 'windows');
      await launcher.openInTerminal(_repo(r'C:\repo'));
      expect(
          fake.calls.map((c) => c.$1).toList(), ['wt.exe', 'powershell']);
    });

    test('windows falls back to cmd when wt and powershell fail', () async {
      final fake = FakeProcessRunner(
          failingExecutables: {'wt.exe', 'powershell'});
      final launcher =
          SystemRepoLauncher(runner: fake, platformOverride: 'windows');
      await launcher.openInTerminal(_repo(r'C:\repo'));
      expect(fake.calls.last.$1, 'cmd');
    });

    test('throws when all fallbacks fail', () async {
      final fake = FakeProcessRunner(
        failingExecutables: {'wt.exe', 'powershell', 'cmd'},
      );
      final launcher =
          SystemRepoLauncher(runner: fake, platformOverride: 'windows');
      expect(
        () => launcher.openInTerminal(_repo(r'C:\repo')),
        throwsA(isA<LauncherException>()),
      );
    });

    test('macos uses open -a Terminal', () async {
      final fake = FakeProcessRunner();
      final launcher =
          SystemRepoLauncher(runner: fake, platformOverride: 'macos');
      await launcher.openInTerminal(_repo('/repo'));
      expect(fake.calls.single.$1, 'open');
      expect(fake.calls.single.$2, ['-a', 'Terminal', '/repo']);
    });

    test('linux tries gnome-terminal first', () async {
      final fake = FakeProcessRunner();
      final launcher =
          SystemRepoLauncher(runner: fake, platformOverride: 'linux');
      await launcher.openInTerminal(_repo('/repo'));
      expect(fake.calls.single.$1, 'gnome-terminal');
    });
  });
}
