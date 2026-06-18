import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/operations/activity_log_store.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/operations/blocking_overlay.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

/// In-memory activity log so the overlay's `operationsProvider` watch does not
/// pull in the real database in a widget test.
class _FakeLogStore implements ActivityLogStore {
  @override
  Future<void> upsert(RunningOperation op) async {}
  @override
  Future<List<RunningOperation>> recent({int limit = 50}) async => const [];
  @override
  Future<void> clearCompleted() async {}
}

void main() {
  testWidgets('hidden when idle, shown + blocks taps when busy',
      (tester) async {
    var tapped = false;
    final container = ProviderContainer(
      overrides: [
        operationsProvider
            .overrideWith((ref) => OperationsNotifier(_FakeLogStore())),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: Stack(
              children: [
                Center(
                  child: GestureDetector(
                    onTap: () => tapped = true,
                    child: const Text('hit me'),
                  ),
                ),
                const BlockingOverlay(),
              ],
            ),
          ),
        ),
      ),
    );

    // Idle: overlay absent, tap passes through.
    expect(find.text('Fetching'), findsNothing);
    await tester.tap(find.text('hit me'));
    expect(tapped, isTrue);

    // Busy: overlay shows its label and absorbs the tap.
    tapped = false;
    container.read(busyProvider.notifier).begin('Fetching');
    await tester.pump();
    expect(find.text('Fetching'), findsOneWidget);
    await tester.tap(find.text('hit me'), warnIfMissed: false);
    expect(tapped, isFalse);

    // Idle again: overlay gone.
    container.read(busyProvider.notifier).end();
    await tester.pump();
    expect(find.text('Fetching'), findsNothing);
  });
}
