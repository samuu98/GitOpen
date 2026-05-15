import 'dart:io';

import '../../application/launcher/process_runner.dart';
import '../../application/launcher/repo_launcher.dart';
import '../../domain/repositories/repo_location.dart';
import 'system_process_runner.dart';

class SystemRepoLauncher implements RepoLauncher {
  final ProcessRunner _runner;
  final String _platform; // 'windows' | 'macos' | 'linux'

  SystemRepoLauncher({
    ProcessRunner? runner,
    String? platformOverride,
  })  : _runner = runner ?? SystemProcessRunner(),
        _platform = platformOverride ?? _detectPlatform();

  static String _detectPlatform() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    return 'linux';
  }

  @override
  Future<void> revealInFiles(RepoLocation repo) async {
    final (exe, args) = switch (_platform) {
      'windows' => ('explorer.exe', [repo.path]),
      'macos' => ('open', [repo.path]),
      _ => ('xdg-open', [repo.path]),
    };
    final ok = await _runner.startDetached(exe, args);
    if (!ok) {
      throw LauncherException('Could not open file manager ($exe).');
    }
  }

  @override
  Future<void> openInTerminal(RepoLocation repo) async {
    throw UnimplementedError();
  }

  @override
  Future<void> openInEditor(RepoLocation repo, EditorTarget editor) async {
    throw UnimplementedError();
  }

  @override
  Future<List<EditorTarget>> detectAvailableEditors() async {
    throw UnimplementedError();
  }
}
