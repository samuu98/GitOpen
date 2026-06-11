import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/refs/tag.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/ui/sidebar/tag_row.dart';
import 'package:gitopen/ui/theme/app_palette.dart';

final _tag = Tag(
  name: 'v1.2.3',
  fullName: 'refs/tags/v1.2.3',
  targetSha: CommitSha('b' * 40),
  isAnnotated: true,
);

/// Ahem-font menu rows overflow by a few pixels in tests only; swallow
/// exactly that error (see branch_tree_view_test.dart).
void ignoreMenuOverflow() {
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed by')) return;
    original?.call(details);
  };
  addTearDown(() => FlutterError.onError = original);
}

Widget _host() => ProviderScope(
  child: MaterialApp(
    theme: ThemeData(extensions: [AppPalette.dark()]),
    home: Scaffold(
      body: TagRow(
        tag: _tag,
        repo: RepoLocation(RepoId.newId(), 'unused', 't'),
        onRefresh: () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('renders the tag name', (tester) async {
    await tester.pumpWidget(_host());
    expect(find.text('v1.2.3'), findsOneWidget);
  });

  testWidgets('context menu offers Checkout / Push tag / Delete tag', (
    tester,
  ) async {
    ignoreMenuOverflow();
    await tester.pumpWidget(_host());
    await tester.tap(find.text('v1.2.3'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Checkout'), findsOneWidget);
    expect(find.text('Push tag'), findsOneWidget);
    expect(find.text('Delete tag'), findsOneWidget);
  });
}
