import 'dart:convert';
import 'dart:io';

import 'secret_storage.dart';

/// Linux [SecretStorage] backed by the Secret Service (GNOME Keyring / KWallet)
/// through the `secret-tool` CLI from libsecret.
///
/// Entries are keyed by the attribute pair (service=[_service], account=key).
/// If `secret-tool` is not installed we fail loudly on writes — never falling
/// back to plaintext — with an actionable message.
class LinuxSecretStorage implements SecretStorage {
  static const _service = 'gitopen';

  static const _missingToolMessage =
      'Cannot store credentials securely: `secret-tool` not found. Install it '
      '(e.g. `sudo apt install libsecret-tools`) and ensure a keyring daemon '
      '(gnome-keyring / KWallet) is running.';

  @override
  Future<String?> read(String key) async {
    try {
      final r = await Process.run(
          'secret-tool', ['lookup', 'service', _service, 'account', key]);
      if (r.exitCode != 0) return null; // not found
      return r.stdout as String; // `lookup` does not append a newline
    } on ProcessException {
      // Tool absent → behave as "no stored credential" for reads.
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final Process proc;
    try {
      proc = await Process.start('secret-tool', [
        'store',
        '--label=GitOpen ($key)',
        'service', _service,
        'account', key,
      ]);
    } on ProcessException {
      throw StateError(_missingToolMessage);
    }
    proc.stdin.add(utf8.encode(value));
    await proc.stdin.close();
    final exit = await proc.exitCode;
    if (exit != 0) {
      final err = await proc.stderr.transform(utf8.decoder).join();
      throw StateError('secret-tool store failed for "$key": $err');
    }
  }

  @override
  Future<void> delete(String key) async {
    try {
      await Process.run(
          'secret-tool', ['clear', 'service', _service, 'account', key]);
    } on ProcessException {
      // Nothing to delete if the tool isn't even present.
    }
  }
}
