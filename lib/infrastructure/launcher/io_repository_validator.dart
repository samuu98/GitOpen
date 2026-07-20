import 'dart:io';

import 'package:gitopen/application/workspaces/repository_validator.dart';
import 'package:path/path.dart' as p;

/// File-system validation for repositories selected in the open-folder flow.
final class IoRepositoryValidator implements RepositoryValidator {
  const IoRepositoryValidator();

  @override
  Future<String> validate(String path) async {
    final trimmed = path.trim();
    final directory = Directory(trimmed);
    if (trimmed.isEmpty || !directory.existsSync()) {
      throw RepositoryValidationException(
        RepositoryValidationError.missing,
        trimmed.isEmpty
            ? 'Choose a repository folder.'
            : 'The folder no longer exists: $trimmed',
      );
    }

    final absolute = p.normalize(directory.absolute.path);
    final gitEntry = p.join(absolute, '.git');
    if (!Directory(gitEntry).existsSync() && !File(gitEntry).existsSync()) {
      throw RepositoryValidationException(
        RepositoryValidationError.notRepository,
        'The selected folder is not a Git repository: $absolute',
      );
    }

    // Resolving links prevents the same checkout being added twice through a
    // junction/symlink. Some network filesystems cannot resolve links; the
    // already-normalized absolute path remains a safe fallback there.
    try {
      return p.normalize(await directory.resolveSymbolicLinks());
    } on FileSystemException {
      return absolute;
    }
  }
}
