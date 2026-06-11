import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// Result of a byte-level file read at some revision.
///
/// Three shapes: missing (`exists == false`), present but over the caller's
/// size cap (`exists, bytes == null`), and loaded (`bytes != null`).
final class FileContent extends Equatable {
  const FileContent({
    required this.exists,
    required this.sizeBytes,
    this.bytes,
  });

  /// The path has no blob at the requested revision (added/deleted diff
  /// sides, root commit's parent, unborn HEAD).
  static const FileContent missing = FileContent(exists: false, sizeBytes: 0);

  final bool exists;
  final int sizeBytes;
  final Uint8List? bytes;

  /// Present but larger than the read's `maxBytes` cap.
  bool get tooLarge => exists && bytes == null;

  @override
  List<Object?> get props => [exists, sizeBytes, bytes];
}
