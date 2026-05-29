import 'dart:io';

import 'secret_storage.dart';

/// macOS Keychain-backed [SecretStorage] using the always-present `security`
/// CLI.  Each entry is a generic password keyed by (service, account) where
/// service is [_service] and account is the storage key.
class MacosKeychainStorage implements SecretStorage {
  static const _service = 'gitopen';

  @override
  Future<String?> read(String key) async {
    final r = await Process.run('security', [
      'find-generic-password',
      '-a', key,
      '-s', _service,
      '-w', // print only the password to stdout
    ]);
    if (r.exitCode != 0) return null; // 44 = item not found
    final out = r.stdout as String;
    // `-w` appends a trailing newline; the stored value never contains one.
    return out.endsWith('\n') ? out.substring(0, out.length - 1) : out;
  }

  @override
  Future<void> write(String key, String value) async {
    final r = await Process.run('security', [
      'add-generic-password',
      '-a', key,
      '-s', _service,
      '-w', value,
      '-U', // update if the item already exists
    ]);
    if (r.exitCode != 0) {
      throw StateError('Keychain write failed for "$key": ${r.stderr}');
    }
  }

  @override
  Future<void> delete(String key) async {
    // Ignore exit code — deleting a missing item is a no-op for our purposes.
    await Process.run('security', [
      'delete-generic-password',
      '-a', key,
      '-s', _service,
    ]);
  }
}
