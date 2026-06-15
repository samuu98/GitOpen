import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/updates/app_release.dart';

void main() {
  const exe = ReleaseAsset(
    name: 'GitOpen-Setup-1.0.0.exe',
    downloadUrl: 'https://example.com/win',
    sizeBytes: 10,
  );
  const deb = ReleaseAsset(
    name: 'gitopen_1.0.0_amd64.deb',
    downloadUrl: 'https://example.com/linux',
    sizeBytes: 20,
  );

  group('selectInstallerAsset', () {
    test('Windows picks the .exe regardless of order', () {
      expect(selectInstallerAsset([deb, exe], InstallerPlatform.windows), exe);
    });

    test('Linux picks the .deb regardless of order', () {
      expect(selectInstallerAsset([exe, deb], InstallerPlatform.linux), deb);
    });

    test('other platform returns null', () {
      expect(
        selectInstallerAsset([exe, deb], InstallerPlatform.other),
        isNull,
      );
    });

    test('returns null when no asset matches the platform', () {
      expect(selectInstallerAsset([deb], InstallerPlatform.windows), isNull);
      expect(selectInstallerAsset([exe], InstallerPlatform.linux), isNull);
    });
  });
}
