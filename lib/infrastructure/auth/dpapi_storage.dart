/// Windows DPAPI-backed credential store.
///
/// Uses [CryptProtectData] / [CryptUnprotectData] (Crypt32.lib) to encrypt
/// values with the current user's Windows key material, then persists them
/// as individual files under [AppData\Roaming\gitopen\credentials].
///
/// No ATL, no MFC, no additional Visual Studio components required — the only
/// native dependency is the win32 package already wired in for other Windows
/// plugins in this project.
library;

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

import 'secret_storage.dart';

/// A simple key-value credential store backed by Windows DPAPI.
///
/// Each entry is stored as an individual binary file:
///   `<roamingAppData>/gitopen/credentials/<key>.bin`
///
/// The blob is DPAPI-protected at rest (per-user, optionally per-machine).
class DpapiStorage implements SecretStorage {
  DpapiStorage._();

  static DpapiStorage? _instance;
  static DpapiStorage get instance => _instance ??= DpapiStorage._();

  /// Resolved once and cached.
  Directory? _credDir;

  Future<Directory> _getCredDir() async {
    if (_credDir != null) return _credDir!;
    final appData = await getApplicationSupportDirectory();
    final dir = Directory('${appData.path}${Platform.pathSeparator}credentials');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _credDir = dir;
    return dir;
  }

  File _fileFor(Directory dir, String key) {
    // Sanitise key so it is safe as a filename.
    final safe = key.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return File('${dir.path}${Platform.pathSeparator}$safe.bin');
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns the stored value for [key], or `null` if absent / unreadable.
  @override
  Future<String?> read(String key) async {
    final dir = await _getCredDir();
    final file = _fileFor(dir, key);
    if (!file.existsSync()) return null;
    try {
      final encrypted = file.readAsBytesSync();
      final plain = _dpApiDecrypt(encrypted);
      if (plain == null) return null;
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  /// Encrypts [value] and stores it under [key].
  @override
  Future<void> write(String key, String value) async {
    final dir = await _getCredDir();
    final file = _fileFor(dir, key);
    final plain = utf8.encode(value);
    final encrypted = _dpApiEncrypt(Uint8List.fromList(plain));
    file.writeAsBytesSync(encrypted, flush: true);
  }

  /// Deletes the entry for [key]. No-op if absent.
  @override
  Future<void> delete(String key) async {
    final dir = await _getCredDir();
    final file = _fileFor(dir, key);
    if (file.existsSync()) file.deleteSync();
  }

  /// Deletes all stored credentials.
  Future<void> deleteAll() async {
    final dir = await _getCredDir();
    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('.bin')) {
        entity.deleteSync();
      }
    }
  }

  /// Returns `true` if a value is stored under [key].
  Future<bool> containsKey(String key) async {
    final dir = await _getCredDir();
    return _fileFor(dir, key).existsSync();
  }

  // ---------------------------------------------------------------------------
  // DPAPI helpers
  // ---------------------------------------------------------------------------

  /// Encrypts [plain] using CryptProtectData (current-user scope).
  ///
  /// Returns the ciphertext blob as [Uint8List].
  Uint8List _dpApiEncrypt(Uint8List plain) {
    return using((Arena arena) {
      // Input DATA_BLOB
      final inBlob = arena<CRYPT_INTEGER_BLOB>();
      final inBytes = arena<ffi.Uint8>(plain.length);
      for (var i = 0; i < plain.length; i++) {
        inBytes[i] = plain[i];
      }
      inBlob.ref.cbData = plain.length;
      inBlob.ref.pbData = inBytes;

      // Output DATA_BLOB (allocated by the API, freed with LocalFree)
      final outBlob = arena<CRYPT_INTEGER_BLOB>();
      outBlob.ref.cbData = 0;
      outBlob.ref.pbData = ffi.nullptr;

      final ok = CryptProtectData(
        inBlob,
        ffi.nullptr, // description
        ffi.nullptr, // optional entropy
        ffi.nullptr, // reserved
        ffi.nullptr, // prompt struct
        0, // flags — CRYPTPROTECT_LOCAL_MACHINE = 4 for machine scope
        outBlob,
      );

      if (ok == 0) {
        throw StateError(
          'CryptProtectData failed: ${GetLastError()}',
        );
      }

      // Copy output before freeing
      final len = outBlob.ref.cbData;
      final result = Uint8List(len);
      for (var i = 0; i < len; i++) {
        result[i] = outBlob.ref.pbData[i];
      }
      LocalFree(outBlob.ref.pbData.cast());

      return result;
    });
  }

  /// Decrypts a DPAPI blob previously produced by [_dpApiEncrypt].
  ///
  /// Returns `null` if decryption fails (e.g. wrong user / corrupted blob).
  Uint8List? _dpApiDecrypt(Uint8List cipher) {
    return using((Arena arena) {
      final inBlob = arena<CRYPT_INTEGER_BLOB>();
      final inBytes = arena<ffi.Uint8>(cipher.length);
      for (var i = 0; i < cipher.length; i++) {
        inBytes[i] = cipher[i];
      }
      inBlob.ref.cbData = cipher.length;
      inBlob.ref.pbData = inBytes;

      final outBlob = arena<CRYPT_INTEGER_BLOB>();
      outBlob.ref.cbData = 0;
      outBlob.ref.pbData = ffi.nullptr;

      final ok = CryptUnprotectData(
        inBlob,
        ffi.nullptr, // description out
        ffi.nullptr, // optional entropy
        ffi.nullptr, // reserved
        ffi.nullptr, // prompt struct
        0, // flags
        outBlob,
      );

      if (ok == 0) return null;

      final len = outBlob.ref.cbData;
      final result = Uint8List(len);
      for (var i = 0; i < len; i++) {
        result[i] = outBlob.ref.pbData[i];
      }
      LocalFree(outBlob.ref.pbData.cast());

      return result;
    });
  }
}
