import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auth/auth_profile.dart';
import 'package:gitopen/application/auth/auth_profile_store.dart';
import 'package:gitopen/application/auth/auth_spec.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/operations/activity_log_store.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/application/providers.dart';
import 'package:gitopen/ui/dialogs/clone_dialog.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

void main() {
  testWidgets('busy clone ignores barrier and Escape; Cancel stops git', (
    tester,
  ) async {
    final stream = StreamController<GitProgress>();
    var stopped = false;
    stream.onCancel = () => stopped = true;
    final write = _CloneWrite(stream.stream);
    final ops = OperationsNotifier(_ActivityStore());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitWriteOperationsProvider.overrideWithValue(write),
          authProfileStoreProvider.overrideWithValue(_Profiles()),
          operationsProvider.overrideWith((ref) => ops),
        ],
        child: MaterialApp(
          theme: ThemeData(extensions: [AppPalette.dark()]),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => CloneDialog.show(context),
                child: const Text('Open clone'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open clone'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).at(0),
      'https://github.com/u/r.git',
    );
    await tester.enterText(find.byType(TextField).at(1), 'C:/repo');
    await tester.tap(find.text('Clone'));
    await tester.pump();
    expect(write.calls, 1);
    expect(write.auth, const AuthHttpsPat(username: 'u', token: 'secret'));
    await tester.tapAt(const Offset(2, 2));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Clone repository'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(stopped, isTrue);
    expect(ops.state.single.status, OperationStatus.cancelled);
    expect(find.text('Clone repository'), findsNothing);
  });
}

final class _CloneWrite implements GitWriteOperations {
  _CloneWrite(this.stream);
  final Stream<GitProgress> stream;
  int calls = 0;
  AuthSpec? auth;

  @override
  Stream<GitProgress> clone(String url, String destination, {AuthSpec? auth}) {
    calls++;
    this.auth = auth;
    return stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

final class _Profiles implements AuthProfileStore {
  @override
  Future<List<AuthProfile>> forHost(String host) async => [
    const AuthProfile(
      id: 'profile',
      host: 'github.com',
      username: 'u',
      spec: AuthHttpsPat(username: 'u', token: 'secret'),
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not faked');
}

final class _ActivityStore implements ActivityLogStore {
  @override
  Future<void> upsert(RunningOperation operation) async {}

  @override
  Future<List<RunningOperation>> recent({int limit = 50}) async => [];

  @override
  Future<void> clearCompleted() async {}
}
