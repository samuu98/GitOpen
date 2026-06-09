import 'dart:io';

import 'package:gitopen/application/launcher/process_runner.dart';
import 'package:gitopen/application/launcher/repo_launcher.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/launcher/system_process_runner.dart';

// Platform values: 'windows' | 'macos' | 'linux'.
class SystemRepoLauncher implements RepoLauncher {

  SystemRepoLauncher({
    ProcessRunner? runner,
    String? platformOverride,
  })  : _runner = runner ?? SystemProcessRunner(),
        _platform = platformOverride ?? _detectPlatform();
  final ProcessRunner _runner;
  final String _platform;

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
    if (_platform == 'windows') {
      // Detached Process.start gives the child no console window — console
      // apps (cmd/powershell) silently die. Route launches through
      // `cmd /c start "" /D <path> <exe>` so Explorer's shell opens a real
      // console for them. Also skips PowerShell 5.1's `-WorkingDirectory`
      // (not supported on Windows PowerShell).
      final candidates = <(String, List<String>)>[
        ('wt.exe', ['-d', repo.path]),
        ('pwsh.exe', ['-NoExit', '-WorkingDirectory', repo.path]),
        ('powershell.exe', ['-NoExit']),
        ('cmd.exe', ['/K']),
      ];
      for (final (exe, exeArgs) in candidates) {
        final probed = await _runner.probe(exe);
        if (!probed.found) continue;
        final ok = await _runner.startDetached(
          'cmd.exe',
          ['/c', 'start', '', '/D', repo.path, exe, ...exeArgs],
        );
        if (ok) return;
      }
      throw const LauncherException(
        'No terminal application available. Install Windows Terminal or '
        'ensure powershell/cmd is on PATH.',
      );
    }
    final chain = _terminalChain(repo.path);
    for (final (exe, args) in chain) {
      final ok = await _runner.startDetached(exe, args);
      if (ok) return;
    }
    throw const LauncherException(
      'No terminal application available. Install gnome-terminal, konsole, '
      'or ensure your default terminal is on PATH.',
    );
  }

  List<(String, List<String>)> _terminalChain(String path) {
    switch (_platform) {
      case 'macos':
        return [
          ('open', ['-a', 'Terminal', path]),
        ];
      default:
        return [
          ('gnome-terminal', ['--working-directory=$path']),
          ('konsole', ['--workdir', path]),
          ('xterm', ['-e', 'cd "$path" && \$SHELL']),
        ];
    }
  }

  @override
  Future<void> openInEditor(RepoLocation repo, EditorTarget editor) async {
    final ok = await _runner.startDetached(editor.executable, [repo.path]);
    if (!ok) {
      throw LauncherException('Could not open ${editor.displayName}.');
    }
  }

  @override
  Future<void> openFileInEditor(
    String editorExecutable,
    String absolutePath,
  ) async {
    final ok = await _runner.startDetached(editorExecutable, [absolutePath]);
    if (!ok) {
      throw LauncherException('Could not open $editorExecutable.');
    }
  }

  List<EditorTarget>? _editorCache;

  static const List<
          ({String id, String displayName, List<String> commands})>
      _editorProbeTable = [
    (id: 'vscode', displayName: 'VS Code', commands: ['code', 'code.cmd']),
    (id: 'cursor', displayName: 'Cursor', commands: ['cursor', 'cursor.cmd']),
    (id: 'idea', displayName: 'IntelliJ IDEA', commands: ['idea64', 'idea']),
    (
      id: 'webstorm',
      displayName: 'WebStorm',
      commands: ['webstorm64', 'webstorm'],
    ),
    (id: 'rider', displayName: 'Rider', commands: ['rider64', 'rider']),
    (id: 'sublime', displayName: 'Sublime Text', commands: ['subl']),
    (
      id: 'studio',
      displayName: 'Android Studio',
      commands: ['studio64', 'studio'],
    ),
    (id: 'fleet', displayName: 'Fleet', commands: ['fleet']),
  ];

  @override
  Future<List<EditorTarget>> detectAvailableEditors() async {
    if (_editorCache != null) return _editorCache!;
    final found = <EditorTarget>[];
    for (final entry in _editorProbeTable) {
      for (final cmd in entry.commands) {
        final result = await _runner.probe(cmd);
        if (result.found) {
          found.add(EditorTarget(
            id: entry.id,
            displayName: entry.displayName,
            executable: result.resolvedPath ?? cmd,
          ));
          break;
        }
      }
    }
    _editorCache = List.unmodifiable(found);
    return _editorCache!;
  }
}
