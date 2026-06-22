import 'dart:io';

import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Append-only file logger.
///
/// Uses synchronous append-mode writes (`writeAsStringSync` with
/// `FileMode.append`).  This is the simplest possible implementation:
/// every line is opened, written, and closed.  At the volumes we log
/// (handful of lines per second at peak) the overhead is irrelevant, and
/// in exchange we get hard guarantees:
///   - no `IOSink` "bound to a stream" races between flush and write
///   - every line on disk before the next instruction runs
///   - safe to call from any zone, including PlatformDispatcher.onError
///
/// A previous IOSink-based implementation looped because flush errors
/// bubbled into the global error handler, which then tried to log the
/// error, which re-entered this output.
class FileLogOutput extends LogOutput {
  String? _path;

  /// Guards the session-start marker so it is written exactly once per
  /// process. [init] is called twice on the same instance: once explicitly
  /// from `main()`, and again by the `Logger` constructor, which propagates
  /// `init()` to every output via `MultiOutput`. Without this guard each
  /// launch wrote two `--- session start ---` lines.
  bool _sessionMarked = false;

  /// Where the log file lives.  Resolved lazily on first use.
  ///
  /// Returns `null` when the platform channel is unavailable — most
  /// commonly in unit tests, where the Flutter binding isn't initialized
  /// so `getApplicationSupportDirectory` throws. In that case the file
  /// sink stays disabled and only the console output remains active.
  Future<String?> resolvePath() async {
    if (_path != null) return _path!;
    try {
      final dir = await getApplicationSupportDirectory();
      final path = p.join(dir.path, 'gitopen.log');
      final f = File(path);
      if (!f.existsSync()) f.createSync(recursive: true);
      return _path = path;
    } on Object catch (_) {
      return null;
    }
  }

  @override
  Future<void> init() async {
    final path = await resolvePath();
    if (path == null) return;
    if (_sessionMarked) return;
    _sessionMarked = true;
    File(path).writeAsStringSync(
      '--- session start ${DateTime.now().toIso8601String()} ---\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  @override
  void output(OutputEvent event) {
    final path = _path;
    if (path == null) return; // init() not yet awaited; drop silently
    try {
      // Build one buffer per event so the underlying syscall happens once.
      final buf = StringBuffer();
      event.lines.forEach(buf.writeln);
      File(path).writeAsStringSync(
        buf.toString(),
        mode: FileMode.append,
        flush: true,
      );
    } on Object catch (_) {
      // NEVER rethrow from a LogOutput.  A throw here would propagate
      // into our global error handlers, which call back into the logger,
      // which would re-throw — a feedback loop that quickly saturates
      // the microtask queue and makes the UI appear to hang.
    }
  }

  @override
  Future<void> destroy() async {}
}
