import 'package:gitopen/application/git/git_action_ports.dart';
import 'package:gitopen/infrastructure/logging/app_logger.dart';

/// [LoggerPort] backed by the app's global [appLog]. Lets UI and application
/// code log through a port instead of importing the infrastructure logger
/// directly (keeps the layering one-directional).
class AppLoggerPort implements LoggerPort {
  const AppLoggerPort();

  @override
  void i(String message) => appLog.i(message);

  @override
  void w(String message) => appLog.w(message);
}
