import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/git_lfs/git_lfs_parsers.dart';

void main() {
  test('parseGitLfsVersion extracts version', () {
    expect(
      parseGitLfsVersion('git-lfs/3.6.1 (GitHub; windows amd64; go 1.23.0)'),
      '3.6.1',
    );
  });

  test('parseGitLfsTrackList parses patterns', () {
    final patterns = parseGitLfsTrackList(
      '*.psd filter=lfs diff=lfs merge=lfs -text\n'
      'assets/** filter=lfs diff=lfs merge=lfs -text\n',
    );

    expect(patterns, hasLength(2));
    expect(patterns.first.pattern, '*.psd');
    expect(patterns.first.attributes, 'filter=lfs diff=lfs merge=lfs -text');
  });

  test('parseGitLfsTrackList skips non-LFS attribute lines', () {
    final patterns = parseGitLfsTrackList(
      '# keep LF on scripts\n'
      '*.sh text eol=lf\n'
      '*.bin filter=lfs diff=lfs merge=lfs -text\n',
    );

    expect(patterns.single.pattern, '*.bin');
  });

  test('parseGitLfsLsFiles parses oid, size, and path', () {
    final files = parseGitLfsLsFiles(
      'a123456789abcdef * big/file.bin (12 MB)\n',
    );

    expect(files.single.oid, 'a123456789abcdef');
    expect(files.single.path, 'big/file.bin');
    expect(files.single.sizeLabel, '12 MB');
  });
}
