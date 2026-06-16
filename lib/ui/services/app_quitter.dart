import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Quits the app. Closing the window exits the process (the native runners are
/// configured to quit on close), which unlocks files for the installer.
typedef AppQuitter = Future<void> Function();

/// Injected so the update flow can quit the app, and tests can stub it.
final appQuitterProvider = Provider<AppQuitter>(
  (ref) => () async => appWindow.close(),
);
