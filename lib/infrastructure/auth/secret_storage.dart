import 'dart:io';

import 'dpapi_storage.dart';
import 'linux_secret_storage.dart';
import 'macos_keychain_storage.dart';

/// Platform-agnostic encrypted key→value secret store.
///
/// Each platform delegates to its OS-native secret backend so tokens are
/// never written in plaintext:
///   - Windows → DPAPI (`CryptProtectData`), see [DpapiStorage]
///   - macOS   → Keychain via the `security` CLI, see [MacosKeychainStorage]
///   - Linux   → Secret Service via `secret-tool` (libsecret), see
///               [LinuxSecretStorage]
///
/// There is intentionally NO plaintext fallback: a backend that cannot store
/// securely throws rather than silently degrading confidentiality.
abstract class SecretStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);

  /// Picks the backend for the current platform.
  factory SecretStorage.forPlatform() {
    if (Platform.isWindows) return DpapiStorage.instance;
    if (Platform.isMacOS) return MacosKeychainStorage();
    if (Platform.isLinux) return LinuxSecretStorage();
    throw UnsupportedError(
        'No secure credential store available on this platform '
        '(${Platform.operatingSystem}).');
  }
}
