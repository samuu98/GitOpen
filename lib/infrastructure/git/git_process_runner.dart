import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../logging/app_logger.dart';

final class GitProcessException implements Exception {
  final List<String> args;
  final int exitCode;
  final String stderr;
  GitProcessException(this.args, this.exitCode, this.stderr);

  /// Args with any `http.extraheader=Authorization: Basic …` value redacted,
  /// so the exception message (and any logs derived from it) never leaks the
  /// in-app credential.
  List<String> get _safeArgs => args
      .map((a) => a.startsWith('http.extraheader=Authorization:')
          ? 'http.extraheader=Authorization: <redacted>'
          : a)
      .toList(growable: false);

  @override
  String toString() => 'git ${_safeArgs.join(' ')} failed ($exitCode): $stderr';
}

class GitProcessRunner {
  final String executable;
  GitProcessRunner({this.executable = 'git'});

  /// Environment overrides applied to every git invocation (merged on top of
  /// the inherited parent environment).
  ///   - `LC_ALL`/`LANG=C` force English, stable messages so our stderr
  ///     classification and "already up to date" detection work regardless of
  ///     the user's system locale.
  ///   - `GIT_TERMINAL_PROMPT=0` makes git fail fast on a missing credential
  ///     instead of blocking forever on an interactive prompt the GUI can
  ///     never answer.
  static const Map<String, String> _env = {
    'LC_ALL': 'C',
    'LANG': 'C',
    'GIT_TERMINAL_PROMPT': '0',
  };

  Future<String> run(String workingDir, List<String> args) async {
    final tag = args.take(3).join(' ');
    final sw = Stopwatch()..start();
    appLog.d('git[$tag] start');
    final result = await Process.run(
      executable,
      args,
      workingDirectory: workingDir,
      environment: _env,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    appLog.d('git[$tag] done in ${sw.elapsedMilliseconds}ms '
        '(exit=${result.exitCode}, stdout=${(result.stdout as String).length}B)');
    if (result.exitCode != 0) {
      throw GitProcessException(
          args, result.exitCode, result.stderr.toString());
    }
    return result.stdout.toString();
  }

  Future<String> runWithStdin(
      String workingDir, List<String> args, String input) async {
    final proc = await Process.start(executable, args,
        workingDirectory: workingDir, environment: _env);
    // Guard the stdin write: if git rejects the input and exits before reading
    // all of it (common with `git apply` on a bad patch), writing to the now
    // broken pipe throws.  Swallow that here — the real failure surfaces via
    // the non-zero exit code and stderr below.
    try {
      proc.stdin.add(utf8.encode(input));
      await proc.stdin.flush();
      await proc.stdin.close();
    } catch (_) {
      // Broken pipe / closed stdin — ignore; exitCode carries the diagnosis.
    }
    final outBuf = StringBuffer();
    final errBuf = StringBuffer();
    await Future.wait([
      proc.stdout.transform(utf8.decoder).forEach(outBuf.write),
      proc.stderr.transform(utf8.decoder).forEach(errBuf.write),
    ]);
    final exit = await proc.exitCode;
    if (exit != 0) throw GitProcessException(args, exit, errBuf.toString());
    return outBuf.toString();
  }

  Stream<String> streamLines(String workingDir, List<String> args) async* {
    final p = await Process.start(executable, args,
        workingDirectory: workingDir, environment: _env);
    final stdoutLines =
        p.stdout.transform(utf8.decoder).transform(const LineSplitter());
    final stderrBuf = StringBuffer();
    // Capture the stderr drain so we can await it before reading the buffer —
    // otherwise a non-zero exit can be observed before stderr is fully
    // collected, yielding a truncated error message.
    final stderrDone =
        p.stderr.transform(utf8.decoder).forEach(stderrBuf.write);
    await for (final line in stdoutLines) {
      yield line;
    }
    final exit = await p.exitCode;
    await stderrDone;
    if (exit != 0) {
      throw GitProcessException(args, exit, stderrBuf.toString());
    }
  }
}
