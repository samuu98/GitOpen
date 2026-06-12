import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/settings/app_settings.dart';

void main() {
  test('autoRefreshEnabled defaults to true', () {
    expect(const AppSettingsState().autoRefreshEnabled, isTrue);
  });

  test('copyWith toggles autoRefreshEnabled and affects equality', () {
    const a = AppSettingsState();
    final b = a.copyWith(autoRefreshEnabled: false);
    expect(b.autoRefreshEnabled, isFalse);
    expect(a == b, isFalse);
  });
}
