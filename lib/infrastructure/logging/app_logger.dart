import 'package:flutter/foundation.dart';
import 'package:gitopen/infrastructure/logging/file_log_output.dart';
import 'package:logger/logger.dart';

/// App-wide logger configured to mirror everything to both the console and
/// an append-only file at `<appSupport>/gitopen.log`.  Use this from any
/// file that needs to trace repo-load lifecycle, native errors, or anything
/// else worth keeping after the process dies.
///
/// `appLogFileOutput.init` must be awaited from `main()` before the first
/// log line is emitted — otherwise the file sink may not be open in time.
final appLogFileOutput = FileLogOutput();

final appLog = Logger(
  // CRITICAL: use [ProductionFilter], not the package default
  // [DevelopmentFilter]. DevelopmentFilter gates `shouldLog` behind an
  // `assert`, so in a release build (asserts stripped) it drops EVERY line —
  // the shipped app wrote nothing but the session markers init() emits
  // directly, making post-mortem after a freeze/crash impossible. With
  // ProductionFilter the file sink works in release too.
  filter: ProductionFilter(),
  // Keep the noisy per-git-command `.d` tracing out of release logs (it fires
  // on every fetch/refresh and would bloat the file + add sync I/O on the hot
  // path); keep it in debug. Lifecycle/startup/warn/error are `.i`+ so they
  // still land in the release log, which is what we need for diagnosis.
  level: kReleaseMode ? Level.info : Level.debug,
  output: MultiOutput([ConsoleOutput(), appLogFileOutput]),
  printer: PrettyPrinter(
    methodCount: 0,
    colors: false,
    printEmojis: false,
  ),
);
