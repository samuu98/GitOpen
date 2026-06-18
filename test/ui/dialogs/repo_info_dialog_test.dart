import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/dialogs/repo_info_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  testWidgets('shows path, origin and identity; copy puts path on clipboard',
      (tester) async {
    const repo = RepoLocation(RepoId('r'), r'C:\repos\demo', 'demo');
    final container = ProviderContainer(
      overrides: [
        repoInfoProvider(repo).overrideWith(
          (ref) async => (
            path: r'C:\repos\demo',
            originUrl: 'https://github.com/o/r.git',
            userName: 'Tester',
            userEmail: 't@e.com',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final copied = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => RepoInfoDialog.show(context, repo: repo),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text(r'C:\repos\demo'), findsOneWidget);
    expect(find.text('https://github.com/o/r.git'), findsOneWidget);
    expect(find.text('Tester <t@e.com>'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.copy_outlined).first);
    await tester.pump();
    expect((copied.single.arguments as Map)['text'], r'C:\repos\demo');
  });
}
