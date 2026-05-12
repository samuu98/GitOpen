# GitOpen Slice 2 (Write/Sync Operations) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the write side of git to GitOpen — commit (file+hunk staging), branch CRUD, fetch/pull/push with progress, stash, merge with conflict detection, cherry-pick, clone — with GitOpen-managed credentials (PAT + SSH + GitHub OAuth Device Flow), an activity panel for long-running ops, and conflict resolution via external editor.

**Architecture:** Layered approach mirrors Slice 1: `GitWriteOperations` interface in `lib/application/git/`, `GitCliWriteOperations` implementation in `lib/infrastructure/git/` shells out to the system `git` binary. Long-running ops return `Stream<GitProgress>` parsed from `git --progress` stderr. Result types (`GitResult<T>` sealed class) over exceptions for expected failures. Credentials stored via `flutter_secure_storage` and injected through a custom Dart credential helper invoked via `GIT_ASKPASS`. Activity log persisted in a new drift table.

**Tech Stack:** Existing Flutter/Dart + drift + Riverpod + bitsdojo_window. New: `flutter_secure_storage`, `url_launcher`, `http`.

**Reading order:** Sub-slices 2A → 2E. Each sub-slice ends in a buildable, testable state. Inside a sub-slice, tasks are sequential.

**Conventions:**
- Repo root: `C:\Users\s.porta\Documents\GitOpen`. Don't touch `legacy/`.
- All git op implementations follow TDD (write failing tests → implement → green → commit).
- Each task ends with: `flutter analyze` 0 issues + `flutter test` (and `flutter build windows --debug` for UI tasks).
- Commits use trailer `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.
- Set `$env:NO_PROXY = "localhost,127.0.0.1"` before `flutter test` (corporate proxy bypass).
- Flutter at `C:\src\flutter\bin\flutter.bat`.
- Kill any running `gitopen.exe` (`Get-Process -Name gitopen -EA SilentlyContinue | Stop-Process -Force`) before `flutter build windows --debug`.

---

## Sub-slice 2A — Foundation

Result types, write contract, operations infrastructure (activity log + toast + activity panel), credentials store, AuthDialog. No actual git write op implementations yet — those land in 2B+.

### Task A1: Add packages and activity_log table

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/infrastructure/persistence/tables/activity_log_table.dart`
- Modify: `lib/infrastructure/persistence/database.dart`

- [ ] **Step 1: Add packages**

```bash
flutter pub add flutter_secure_storage url_launcher http
```

- [ ] **Step 2: Create `activity_log_table.dart`**

```dart
import 'package:drift/drift.dart';

class ActivityLog extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get opId => text()();
  TextColumn get kind => text()();
  TextColumn get label => text()();
  TextColumn get repoId => text().nullable()();
  TextColumn get status => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  TextColumn get stderr => text().nullable()();
  TextColumn get errorMessage => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
```

- [ ] **Step 3: Wire into `database.dart`**

Add `ActivityLog` to `@DriftDatabase(tables: [Repositories, Settings, ActivityLog])` and bump `schemaVersion` to `2`. Override `migration`:

```dart
@override
MigrationStrategy get migration => MigrationStrategy(
  onUpgrade: (m, from, to) async {
    if (from < 2) {
      await m.createTable(activityLog);
    }
  },
);
```

Add `import 'tables/activity_log_table.dart';`.

- [ ] **Step 4: Run codegen + build**

```powershell
& 'C:\src\flutter\bin\flutter.bat' pub get
dart run build_runner build --delete-conflicting-outputs
& 'C:\src\flutter\bin\flutter.bat' analyze
```

Expected: 0 issues.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/infrastructure/persistence
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(infra): drift activity_log table + auth/url/http packages

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task A2: GitResult / GitErrorKind sealed class

**Files:**
- Create: `lib/application/git/git_result.dart`
- Create: `test/application/git/git_result_test.dart`

- [ ] **Step 1: Failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';

void main() {
  group('GitResult', () {
    test('GitSuccess holds value', () {
      const r = GitSuccess<int>(42);
      expect(r.value, 42);
    });

    test('GitFailure has kind and message', () {
      const r = GitFailure<int>(GitErrorKind.auth, 'bad token', 'fatal: 401');
      expect(r.kind, GitErrorKind.auth);
      expect(r.message, 'bad token');
      expect(r.rawOutput, 'fatal: 401');
    });

    test('switch is exhaustive', () {
      const r = GitSuccess<String>('ok');
      final out = switch (r) {
        GitSuccess(value: final v) => v,
        GitFailure() => 'err',
      };
      expect(out, 'ok');
    });
  });
}
```

- [ ] **Step 2: Run failing**

```powershell
$env:NO_PROXY="localhost,127.0.0.1"; & 'C:\src\flutter\bin\flutter.bat' test test/application/git/git_result_test.dart
```

Expected: compile error (type not defined).

- [ ] **Step 3: Implement**

```dart
sealed class GitResult<T> {
  const GitResult();
}

final class GitSuccess<T> extends GitResult<T> {
  final T value;
  const GitSuccess(this.value);
}

final class GitFailure<T> extends GitResult<T> {
  final GitErrorKind kind;
  final String message;
  final String? rawOutput;
  const GitFailure(this.kind, this.message, [this.rawOutput]);
}

enum GitErrorKind {
  network,
  auth,
  conflict,
  nonFastForward,
  dirtyWorkingTree,
  unknownRef,
  invalidArgument,
  other,
}
```

- [ ] **Step 4: Tests pass**

```powershell
& 'C:\src\flutter\bin\flutter.bat' test test/application/git/git_result_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/application/git/git_result.dart test
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(app): GitResult sealed types + GitErrorKind"
```

---

### Task A3: GitProgress + GitProgressParser

**Files:**
- Create: `lib/application/git/git_progress.dart`
- Create: `lib/infrastructure/git/git_progress_parser.dart`
- Create: `test/infrastructure/git/git_progress_parser_test.dart`

- [ ] **Step 1: Types** at `lib/application/git/git_progress.dart`:

```dart
final class GitProgress {
  final String phase;
  final double? fraction;
  final String rawLine;
  const GitProgress({required this.phase, this.fraction, required this.rawLine});
}
```

- [ ] **Step 2: Failing parser tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/git/git_progress_parser.dart';

void main() {
  group('GitProgressParser', () {
    test('parses Counting line', () {
      final p = GitProgressParser.parse('Counting objects:  45% (180/400)');
      expect(p, isNotNull);
      expect(p!.phase, 'Counting objects');
      expect(p.fraction, closeTo(0.45, 0.001));
    });

    test('parses remote: Receiving', () {
      final p = GitProgressParser.parse('remote: Receiving objects:  23% (92/400)');
      expect(p!.phase, 'Receiving objects');
      expect(p.fraction, closeTo(0.23, 0.001));
    });

    test('returns null for non-progress lines', () {
      expect(GitProgressParser.parse('fatal: not a git repository'), isNull);
      expect(GitProgressParser.parse(''), isNull);
    });
  });
}
```

- [ ] **Step 3: Implement**

```dart
import '../../application/git/git_progress.dart';

class GitProgressParser {
  static final _regex = RegExp(r'^(?:remote:\s*)?(?<phase>[^:]+):\s+(?<pct>\d+)%');

  static GitProgress? parse(String line) {
    final m = _regex.firstMatch(line);
    if (m == null) return null;
    final phase = m.namedGroup('phase')!.trim();
    final pct = int.parse(m.namedGroup('pct')!);
    return GitProgress(phase: phase, fraction: pct / 100.0, rawLine: line);
  }
}
```

- [ ] **Step 4: Tests pass + commit**

```bash
& 'C:\src\flutter\bin\flutter.bat' test test/infrastructure/git/git_progress_parser_test.dart
git add lib test
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(infra): GitProgress + parser for git --progress stderr"
```

---

### Task A4: GitWriteOperations contract + skeleton

**Files:**
- Create: `lib/application/git/git_write_operations.dart`
- Create: `lib/application/git/commit_request.dart`
- Create: `lib/application/git/auth_spec.dart`
- Create: `lib/application/git/merge_outcome.dart`
- Create: `lib/infrastructure/git/git_cli_write_operations.dart`

- [ ] **Step 1: AuthSpec sealed class** at `lib/application/git/auth_spec.dart`:

```dart
sealed class AuthSpec {
  const AuthSpec();
}

final class AuthHttpsPat extends AuthSpec {
  final String username;
  final String token;
  const AuthHttpsPat({required this.username, required this.token});
}

final class AuthHttpsBasic extends AuthSpec {
  final String username;
  final String password;
  const AuthHttpsBasic({required this.username, required this.password});
}

final class AuthSsh extends AuthSpec {
  final String privateKeyPath;
  final String? passphrase;
  const AuthSsh({required this.privateKeyPath, this.passphrase});
}

final class AuthGitHubOauth extends AuthSpec {
  final String accessToken;
  const AuthGitHubOauth(this.accessToken);
}

final class AuthSystemDefault extends AuthSpec {
  const AuthSystemDefault();
}
```

- [ ] **Step 2: CommitRequest** at `lib/application/git/commit_request.dart`:

```dart
final class CommitRequest {
  final String message;
  final bool amend;
  final bool signOff;
  final String? authorName;
  final String? authorEmail;

  const CommitRequest({
    required this.message,
    this.amend = false,
    this.signOff = false,
    this.authorName,
    this.authorEmail,
  });
}
```

- [ ] **Step 3: MergeOutcome / CherryPickOutcome** at `lib/application/git/merge_outcome.dart`:

```dart
import '../../domain/commits/commit_sha.dart';

sealed class MergeOutcome {
  const MergeOutcome();
}

final class MergeFastForward extends MergeOutcome {
  final CommitSha newHead;
  const MergeFastForward(this.newHead);
}

final class MergeMerged extends MergeOutcome {
  final CommitSha mergeCommit;
  const MergeMerged(this.mergeCommit);
}

final class MergeConflict extends MergeOutcome {
  final List<String> conflictedPaths;
  const MergeConflict(this.conflictedPaths);
}

sealed class CherryPickOutcome {
  const CherryPickOutcome();
}

final class CherryPickApplied extends CherryPickOutcome {
  final CommitSha newCommit;
  const CherryPickApplied(this.newCommit);
}

final class CherryPickConflict extends CherryPickOutcome {
  final List<String> conflictedPaths;
  const CherryPickConflict(this.conflictedPaths);
}
```

- [ ] **Step 4: GitWriteOperations interface** at `lib/application/git/git_write_operations.dart`:

```dart
import '../../domain/commits/commit_sha.dart';
import '../../domain/repositories/repo_location.dart';
import 'auth_spec.dart';
import 'commit_request.dart';
import 'git_progress.dart';
import 'git_result.dart';
import 'merge_outcome.dart';

enum PullStrategy { ffOnly, merge, rebase }
enum ResetMode { soft, mixed, hard }

abstract interface class GitWriteOperations {
  Future<GitResult<void>> stageFiles(RepoLocation r, List<String> paths);
  Future<GitResult<void>> unstageFiles(RepoLocation r, List<String> paths);
  Future<GitResult<void>> stagePatch(RepoLocation r, String unifiedDiff);
  Future<GitResult<void>> unstagePatch(RepoLocation r, String unifiedDiff);
  Future<GitResult<void>> discardChanges(RepoLocation r, List<String> paths);

  Future<GitResult<CommitSha>> commit(RepoLocation r, CommitRequest req);

  Future<GitResult<void>> createBranch(RepoLocation r, String name,
      {CommitSha? at, bool checkout = false});
  Future<GitResult<void>> checkout(RepoLocation r, String ref, {bool force = false});
  Future<GitResult<void>> deleteBranch(RepoLocation r, String name,
      {bool force = false, bool remote = false});
  Future<GitResult<void>> renameBranch(RepoLocation r, String oldName, String newName);
  Future<GitResult<void>> setUpstream(RepoLocation r, String branch, String upstream);
  Future<GitResult<void>> createTag(RepoLocation r, String name,
      {CommitSha? at, String? message});
  Future<GitResult<void>> deleteTag(RepoLocation r, String name);

  Stream<GitProgress> fetch(RepoLocation r, {String? remote, bool all = false, AuthSpec? auth});
  Stream<GitProgress> pull(RepoLocation r, PullStrategy strategy, {AuthSpec? auth});
  Stream<GitProgress> push(RepoLocation r,
      {String? remote, String? branch, bool forceWithLease = false, bool pushTags = false, AuthSpec? auth});

  Future<GitResult<void>> stashSave(RepoLocation r, String message, {bool includeUntracked = false});
  Future<GitResult<void>> stashPop(RepoLocation r, int index);
  Future<GitResult<void>> stashApply(RepoLocation r, int index);
  Future<GitResult<void>> stashDrop(RepoLocation r, int index);

  Future<GitResult<MergeOutcome>> merge(RepoLocation r, String ref,
      {bool ffOnly = false, bool noCommit = false});
  Future<GitResult<void>> mergeAbort(RepoLocation r);
  Future<GitResult<CommitSha>> mergeContinue(RepoLocation r);

  Future<GitResult<CherryPickOutcome>> cherryPick(RepoLocation r, CommitSha sha);
  Future<GitResult<void>> cherryPickAbort(RepoLocation r);
  Future<GitResult<CommitSha>> cherryPickContinue(RepoLocation r);

  Future<GitResult<void>> reset(RepoLocation r, CommitSha to, ResetMode mode);

  Stream<GitProgress> clone(String url, String destination, {AuthSpec? auth});
}
```

- [ ] **Step 5: Skeleton implementation** at `lib/infrastructure/git/git_cli_write_operations.dart`:

```dart
import '../../application/git/auth_spec.dart';
import '../../application/git/commit_request.dart';
import '../../application/git/git_progress.dart';
import '../../application/git/git_result.dart';
import '../../application/git/git_write_operations.dart';
import '../../application/git/merge_outcome.dart';
import '../../domain/commits/commit_sha.dart';
import '../../domain/repositories/repo_location.dart';
import 'git_process_runner.dart';

final class GitCliWriteOperations implements GitWriteOperations {
  // ignore: unused_field
  final GitProcessRunner _runner;
  GitCliWriteOperations({GitProcessRunner? runner})
      : _runner = runner ?? GitProcessRunner();

  @override
  Future<GitResult<void>> stageFiles(RepoLocation r, List<String> paths) => throw UnimplementedError();
  @override
  Future<GitResult<void>> unstageFiles(RepoLocation r, List<String> paths) => throw UnimplementedError();
  @override
  Future<GitResult<void>> stagePatch(RepoLocation r, String unifiedDiff) => throw UnimplementedError();
  @override
  Future<GitResult<void>> unstagePatch(RepoLocation r, String unifiedDiff) => throw UnimplementedError();
  @override
  Future<GitResult<void>> discardChanges(RepoLocation r, List<String> paths) => throw UnimplementedError();
  @override
  Future<GitResult<CommitSha>> commit(RepoLocation r, CommitRequest req) => throw UnimplementedError();
  @override
  Future<GitResult<void>> createBranch(RepoLocation r, String name, {CommitSha? at, bool checkout = false}) => throw UnimplementedError();
  @override
  Future<GitResult<void>> checkout(RepoLocation r, String ref, {bool force = false}) => throw UnimplementedError();
  @override
  Future<GitResult<void>> deleteBranch(RepoLocation r, String name, {bool force = false, bool remote = false}) => throw UnimplementedError();
  @override
  Future<GitResult<void>> renameBranch(RepoLocation r, String oldName, String newName) => throw UnimplementedError();
  @override
  Future<GitResult<void>> setUpstream(RepoLocation r, String branch, String upstream) => throw UnimplementedError();
  @override
  Future<GitResult<void>> createTag(RepoLocation r, String name, {CommitSha? at, String? message}) => throw UnimplementedError();
  @override
  Future<GitResult<void>> deleteTag(RepoLocation r, String name) => throw UnimplementedError();
  @override
  Stream<GitProgress> fetch(RepoLocation r, {String? remote, bool all = false, AuthSpec? auth}) => throw UnimplementedError();
  @override
  Stream<GitProgress> pull(RepoLocation r, PullStrategy strategy, {AuthSpec? auth}) => throw UnimplementedError();
  @override
  Stream<GitProgress> push(RepoLocation r, {String? remote, String? branch, bool forceWithLease = false, bool pushTags = false, AuthSpec? auth}) => throw UnimplementedError();
  @override
  Future<GitResult<void>> stashSave(RepoLocation r, String message, {bool includeUntracked = false}) => throw UnimplementedError();
  @override
  Future<GitResult<void>> stashPop(RepoLocation r, int index) => throw UnimplementedError();
  @override
  Future<GitResult<void>> stashApply(RepoLocation r, int index) => throw UnimplementedError();
  @override
  Future<GitResult<void>> stashDrop(RepoLocation r, int index) => throw UnimplementedError();
  @override
  Future<GitResult<MergeOutcome>> merge(RepoLocation r, String ref, {bool ffOnly = false, bool noCommit = false}) => throw UnimplementedError();
  @override
  Future<GitResult<void>> mergeAbort(RepoLocation r) => throw UnimplementedError();
  @override
  Future<GitResult<CommitSha>> mergeContinue(RepoLocation r) => throw UnimplementedError();
  @override
  Future<GitResult<CherryPickOutcome>> cherryPick(RepoLocation r, CommitSha sha) => throw UnimplementedError();
  @override
  Future<GitResult<void>> cherryPickAbort(RepoLocation r) => throw UnimplementedError();
  @override
  Future<GitResult<CommitSha>> cherryPickContinue(RepoLocation r) => throw UnimplementedError();
  @override
  Future<GitResult<void>> reset(RepoLocation r, CommitSha to, ResetMode mode) => throw UnimplementedError();
  @override
  Stream<GitProgress> clone(String url, String destination, {AuthSpec? auth}) => throw UnimplementedError();
}
```

- [ ] **Step 6: Register in providers** — append to `lib/application/providers.dart`:

```dart
final gitWriteOperationsProvider = Provider<GitWriteOperations>((ref) {
  return GitCliWriteOperations(runner: ref.watch(gitProcessRunnerProvider));
});
```

(Add the necessary imports.)

- [ ] **Step 7: Build + commit**

```powershell
& 'C:\src\flutter\bin\flutter.bat' analyze
```

```bash
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(app): GitWriteOperations contract + CLI skeleton

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task A5: RunningOperation + OperationsNotifier

**Files:**
- Create: `lib/application/operations/running_operation.dart`
- Create: `lib/application/operations/operations_notifier.dart`
- Create: `lib/infrastructure/operations/activity_log_repository.dart`
- Create: `test/application/operations/operations_notifier_test.dart`

- [ ] **Step 1: RunningOperation** at `lib/application/operations/running_operation.dart`:

```dart
import 'dart:io';
import 'package:equatable/equatable.dart';
import '../../domain/repositories/repo_location.dart';

enum OpKind { fetch, pull, push, clone, commit, merge, cherryPick, stash, branch, reset, other }
enum OperationStatus { pending, running, success, failed, cancelled }

class RunningOperation extends Equatable {
  final String id;
  final OpKind kind;
  final String label;
  final RepoLocation? repo;
  final OperationStatus status;
  final double? progress;
  final String phase;
  final List<String> stderrTail;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final Process? process;
  final String? errorMessage;

  const RunningOperation({
    required this.id,
    required this.kind,
    required this.label,
    this.repo,
    this.status = OperationStatus.pending,
    this.progress,
    this.phase = '',
    this.stderrTail = const [],
    required this.startedAt,
    this.finishedAt,
    this.process,
    this.errorMessage,
  });

  RunningOperation copyWith({
    OperationStatus? status,
    double? progress,
    String? phase,
    List<String>? stderrTail,
    DateTime? finishedAt,
    Process? process,
    String? errorMessage,
  }) {
    return RunningOperation(
      id: id, kind: kind, label: label, repo: repo, startedAt: startedAt,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      phase: phase ?? this.phase,
      stderrTail: stderrTail ?? this.stderrTail,
      finishedAt: finishedAt ?? this.finishedAt,
      process: process ?? this.process,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [id, status, progress, phase, finishedAt];
}
```

- [ ] **Step 2: ActivityLogRepository** at `lib/infrastructure/operations/activity_log_repository.dart`:

```dart
import 'package:drift/drift.dart';
import '../../application/operations/running_operation.dart';
import '../persistence/database.dart';

class ActivityLogRepository {
  final AppDatabase _db;
  ActivityLogRepository(this._db);

  Future<void> upsert(RunningOperation op) async {
    final existing = await (_db.select(_db.activityLog)..where((t) => t.opId.equals(op.id))).getSingleOrNull();
    final companion = ActivityLogCompanion(
      opId: Value(op.id),
      kind: Value(op.kind.name),
      label: Value(op.label),
      repoId: Value(op.repo?.id.value),
      status: Value(op.status.name),
      startedAt: Value(op.startedAt),
      finishedAt: Value(op.finishedAt),
      stderr: Value(op.stderrTail.isEmpty ? null : op.stderrTail.join('\n')),
      errorMessage: Value(op.errorMessage),
    );
    if (existing == null) {
      await _db.into(_db.activityLog).insert(companion);
    } else {
      await (_db.update(_db.activityLog)..where((t) => t.opId.equals(op.id))).write(companion);
    }
  }

  Future<List<RunningOperation>> recent({int limit = 50}) async {
    final rows = await (_db.select(_db.activityLog)..orderBy([(t) => OrderingTerm.desc(t.startedAt)])..limit(limit)).get();
    return rows.map(_toOp).toList();
  }

  Future<void> clearCompleted() async {
    await (_db.delete(_db.activityLog)..where((t) => t.status.isNotIn(['running', 'pending']))).go();
  }

  RunningOperation _toOp(ActivityLogData row) {
    return RunningOperation(
      id: row.opId,
      kind: OpKind.values.byName(row.kind),
      label: row.label,
      repo: null, // recovered repo from row.repoId if needed by caller
      status: OperationStatus.values.byName(row.status),
      startedAt: row.startedAt,
      finishedAt: row.finishedAt,
      stderrTail: (row.stderr ?? '').split('\n').where((s) => s.isNotEmpty).toList(),
      errorMessage: row.errorMessage,
    );
  }
}
```

- [ ] **Step 3: OperationsNotifier** at `lib/application/operations/operations_notifier.dart`:

```dart
import 'dart:io';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/repositories/repo_location.dart';
import '../../infrastructure/operations/activity_log_repository.dart';
import 'running_operation.dart';

class OperationsNotifier extends StateNotifier<List<RunningOperation>> {
  final ActivityLogRepository _log;
  static const _stderrMax = 50;

  OperationsNotifier(this._log) : super(const []) {
    _hydrate();
  }

  Future<void> _hydrate() async {
    final recent = await _log.recent();
    // Any "running" row from a previous session is stale — mark failed.
    final cleaned = recent.map((op) {
      if (op.status == OperationStatus.running || op.status == OperationStatus.pending) {
        return op.copyWith(status: OperationStatus.failed, errorMessage: 'Interrupted by app close', finishedAt: DateTime.now());
      }
      return op;
    }).toList();
    state = cleaned;
  }

  String start(OpKind kind, String label, {RepoLocation? repo, Process? process}) {
    final id = _id();
    final op = RunningOperation(
      id: id,
      kind: kind,
      label: label,
      repo: repo,
      status: OperationStatus.running,
      startedAt: DateTime.now(),
      process: process,
    );
    state = [op, ...state];
    _log.upsert(op);
    return id;
  }

  void updateProgress(String id, double? fraction, String phase) {
    _update(id, (op) => op.copyWith(progress: fraction, phase: phase));
  }

  void appendStderr(String id, String line) {
    _update(id, (op) {
      final next = [...op.stderrTail, line];
      if (next.length > _stderrMax) next.removeAt(0);
      return op.copyWith(stderrTail: next);
    });
  }

  void finishSuccess(String id) {
    _update(id, (op) => op.copyWith(status: OperationStatus.success, finishedAt: DateTime.now()));
  }

  void finishFailure(String id, String message) {
    _update(id, (op) => op.copyWith(status: OperationStatus.failed, finishedAt: DateTime.now(), errorMessage: message));
  }

  void cancel(String id) {
    final op = state.firstWhere((o) => o.id == id, orElse: () => throw StateError('no op $id'));
    op.process?.kill();
    _update(id, (o) => o.copyWith(status: OperationStatus.cancelled, finishedAt: DateTime.now()));
  }

  Future<void> clearCompleted() async {
    state = state.where((o) => o.status == OperationStatus.running || o.status == OperationStatus.pending).toList();
    await _log.clearCompleted();
  }

  void _update(String id, RunningOperation Function(RunningOperation) f) {
    state = state.map((o) => o.id == id ? f(o) : o).toList();
    final updated = state.firstWhere((o) => o.id == id, orElse: () => throw StateError('no op $id'));
    _log.upsert(updated);
  }

  String _id() => '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 32).toRadixString(16)}';
}
```

- [ ] **Step 4: Provider** in `lib/application/providers.dart` append:

```dart
final activityLogRepositoryProvider = Provider<ActivityLogRepository>((ref) {
  return ActivityLogRepository(ref.watch(appDatabaseProvider));
});

final operationsProvider = StateNotifierProvider<OperationsNotifier, List<RunningOperation>>((ref) {
  return OperationsNotifier(ref.watch(activityLogRepositoryProvider));
});
```

Add the imports.

- [ ] **Step 5: Smoke test** at `test/application/operations/operations_notifier_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/operations/operations_notifier.dart';
import 'package:gitopen/application/operations/running_operation.dart';
import 'package:gitopen/infrastructure/operations/activity_log_repository.dart';
import '../../_helpers/in_memory_db.dart';

void main() {
  test('start + finishSuccess transitions state and persists', () async {
    final db = newInMemoryDb();
    final notifier = OperationsNotifier(ActivityLogRepository(db));
    await Future.delayed(const Duration(milliseconds: 50)); // let hydrate
    final id = notifier.start(OpKind.fetch, 'Fetching origin');
    expect(notifier.state, hasLength(1));
    expect(notifier.state.first.status, OperationStatus.running);
    notifier.finishSuccess(id);
    expect(notifier.state.first.status, OperationStatus.success);
    await db.close();
  });
}
```

- [ ] **Step 6: Run + commit**

```bash
& 'C:\src\flutter\bin\flutter.bat' test test/application/operations
& 'C:\src\flutter\bin\flutter.bat' analyze
git add lib test
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(app): OperationsNotifier + ActivityLogRepository drift-persisted"
```

---

### Task A6: Toast overlay widget

**Files:**
- Create: `lib/ui/operations/toast_overlay.dart`
- Modify: `lib/main.dart` (wrap Shell body in Stack with the overlay)

- [ ] **Step 1: ToastOverlay widget**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/operations/operations_notifier.dart';
import '../../application/operations/running_operation.dart';
import '../../application/providers.dart';
import 'activity_panel.dart';

class ToastOverlay extends ConsumerWidget {
  const ToastOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ops = ref.watch(operationsProvider);
    // Take running ops + recently finished failures (last 5s) for display
    final now = DateTime.now();
    final visible = ops.where((o) {
      if (o.status == OperationStatus.running || o.status == OperationStatus.pending) return true;
      if (o.status == OperationStatus.failed && o.finishedAt != null
          && now.difference(o.finishedAt!) < const Duration(seconds: 10)) return true;
      if (o.status == OperationStatus.success && o.finishedAt != null
          && now.difference(o.finishedAt!) < const Duration(seconds: 3)) return true;
      return false;
    }).take(3).toList();

    if (visible.isEmpty) return const SizedBox.shrink();

    return Positioned(
      right: 12,
      bottom: 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final op in visible) _ToastItem(op: op),
        ],
      ),
    );
  }
}

class _ToastItem extends ConsumerWidget {
  final RunningOperation op;
  const _ToastItem({required this.op});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isError = op.status == OperationStatus.failed;
    final isRunning = op.status == OperationStatus.running;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxWidth: 360, minWidth: 280),
      decoration: BoxDecoration(
        color: const Color(0xFF25252A),
        border: Border.all(color: isError ? const Color(0xFFC4314B) : const Color(0xFF404048)),
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: InkWell(
        onTap: () => _openActivityPanel(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (isRunning) const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  if (!isRunning) Icon(isError ? Icons.error_outline : Icons.check_circle_outline,
                      size: 16, color: isError ? const Color(0xFFC4314B) : const Color(0xFF4EC9B0)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(op.label, style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 12.5))),
                  if (isRunning)
                    IconButton(
                      icon: const Icon(Icons.close, size: 14, color: Color(0xFF888892)),
                      onPressed: () => ref.read(operationsProvider.notifier).cancel(op.id),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      tooltip: 'Cancel',
                    ),
                ],
              ),
              if (isRunning) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(value: op.progress, minHeight: 3),
                if (op.phase.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(op.phase, style: const TextStyle(color: Color(0xFF888892), fontSize: 11)),
                  ),
              ],
              if (isError && op.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(op.errorMessage!, style: const TextStyle(color: Color(0xFFC4314B), fontSize: 11)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openActivityPanel(BuildContext context) {
    showDialog(context: context, builder: (_) => const ActivityPanel());
  }
}
```

- [ ] **Step 2: ActivityPanel** at `lib/ui/operations/activity_panel.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/operations/operations_notifier.dart';
import '../../application/operations/running_operation.dart';
import '../../application/providers.dart';

class ActivityPanel extends ConsumerWidget {
  const ActivityPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ops = ref.watch(operationsProvider);
    return Dialog(
      backgroundColor: const Color(0xFF1F1F23),
      child: SizedBox(
        width: 560,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Text('Activity', style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => ref.read(operationsProvider.notifier).clearCompleted(),
                    child: const Text('Clear completed'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Color(0xFFB8B8BC)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF313137)),
            Expanded(
              child: ListView.builder(
                itemCount: ops.length,
                itemBuilder: (_, i) => _Row(op: ops[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatefulWidget {
  final RunningOperation op;
  const _Row({required this.op});
  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final op = widget.op;
    IconData icon; Color color;
    switch (op.status) {
      case OperationStatus.running:
      case OperationStatus.pending:
        icon = Icons.refresh; color = const Color(0xFF6FA8DC); break;
      case OperationStatus.success:
        icon = Icons.check_circle; color = const Color(0xFF4EC9B0); break;
      case OperationStatus.failed:
        icon = Icons.error; color = const Color(0xFFC4314B); break;
      case OperationStatus.cancelled:
        icon = Icons.block; color = const Color(0xFF888892); break;
    }
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(op.label, style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 12.5))),
              Text(op.startedAt.toLocal().toString().substring(11, 19),
                  style: const TextStyle(color: Color(0xFF5D5D65), fontSize: 11)),
            ]),
            if (_expanded && op.stderrTail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 22),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFF25252A), borderRadius: BorderRadius.circular(4)),
                  child: Text(op.stderrTail.join('\n'),
                      style: const TextStyle(color: Color(0xFFB8B8BC), fontSize: 11, fontFamily: 'monospace')),
                ),
              ),
            if (_expanded && op.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 22),
                child: Text(op.errorMessage!, style: const TextStyle(color: Color(0xFFC4314B), fontSize: 11)),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Wire ToastOverlay into Shell** — in `lib/main.dart` wrap the `WindowBorder.child` Column inside a `Stack`:

```dart
body: WindowBorder(
  color: const Color(0xFF2C2C31),
  width: 1,
  child: Stack(children: [
    Column(children: [
      const _TitleBar(),
      Expanded(child: /* existing body */),
    ]),
    const ToastOverlay(),
  ]),
),
```

Add `import 'ui/operations/toast_overlay.dart';`.

- [ ] **Step 4: Build + commit**

```bash
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(ui): ToastOverlay + ActivityPanel wired into Shell"
```

---

### Task A7: SecureCredentialsStore + AuthSpec serialization

**Files:**
- Create: `lib/application/auth/credentials_store.dart`
- Create: `lib/infrastructure/auth/secure_credentials_store.dart`
- Create: `test/infrastructure/auth/secure_credentials_store_test.dart` (skipped on CI — uses real keychain)

- [ ] **Step 1: Interface** at `lib/application/auth/credentials_store.dart`:

```dart
import '../git/auth_spec.dart';

abstract interface class CredentialsStore {
  Future<AuthSpec?> get(String host);
  Future<void> put(String host, AuthSpec spec);
  Future<void> delete(String host);
  Future<List<String>> hosts();
}
```

- [ ] **Step 2: Implementation** at `lib/infrastructure/auth/secure_credentials_store.dart`:

```dart
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../application/auth/credentials_store.dart';
import '../../application/git/auth_spec.dart';

class SecureCredentialsStore implements CredentialsStore {
  static const _prefix = 'gitopen:auth:';
  final FlutterSecureStorage _storage;
  SecureCredentialsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<AuthSpec?> get(String host) async {
    final json = await _storage.read(key: '$_prefix$host');
    if (json == null) return null;
    return _decode(json);
  }

  @override
  Future<void> put(String host, AuthSpec spec) async {
    await _storage.write(key: '$_prefix$host', value: _encode(spec));
  }

  @override
  Future<void> delete(String host) async {
    await _storage.delete(key: '$_prefix$host');
  }

  @override
  Future<List<String>> hosts() async {
    final all = await _storage.readAll();
    return all.keys
        .where((k) => k.startsWith(_prefix))
        .map((k) => k.substring(_prefix.length))
        .toList();
  }

  String _encode(AuthSpec spec) {
    final map = switch (spec) {
      AuthHttpsPat() => {'kind': 'pat', 'username': spec.username, 'token': spec.token},
      AuthHttpsBasic() => {'kind': 'basic', 'username': spec.username, 'password': spec.password},
      AuthSsh() => {'kind': 'ssh', 'keyPath': spec.privateKeyPath, 'passphrase': spec.passphrase},
      AuthGitHubOauth() => {'kind': 'github', 'token': spec.accessToken},
      AuthSystemDefault() => {'kind': 'system'},
    };
    return jsonEncode(map);
  }

  AuthSpec _decode(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    switch (m['kind']) {
      case 'pat': return AuthHttpsPat(username: m['username'], token: m['token']);
      case 'basic': return AuthHttpsBasic(username: m['username'], password: m['password']);
      case 'ssh': return AuthSsh(privateKeyPath: m['keyPath'], passphrase: m['passphrase']);
      case 'github': return AuthGitHubOauth(m['token']);
      case 'system': return const AuthSystemDefault();
      default: throw FormatException('Unknown auth kind: ${m['kind']}');
    }
  }
}
```

- [ ] **Step 3: Provider** in `lib/application/providers.dart`:

```dart
final credentialsStoreProvider = Provider<CredentialsStore>((ref) => SecureCredentialsStore());
```

Add imports.

- [ ] **Step 4: Build + commit**

```bash
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(infra): SecureCredentialsStore via flutter_secure_storage"
```

---

### Task A8: AuthDialog widget

**Files:**
- Create: `lib/ui/dialogs/auth_dialog.dart`

- [ ] **Step 1: Widget**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/git/auth_spec.dart';
import '../../application/providers.dart';

class AuthDialog extends ConsumerStatefulWidget {
  final String host;
  const AuthDialog({super.key, required this.host});

  static Future<AuthSpec?> show(BuildContext context, String host) {
    return showDialog<AuthSpec>(context: context, builder: (_) => AuthDialog(host: host));
  }

  @override
  ConsumerState<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends ConsumerState<AuthDialog> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _userCtl = TextEditingController();
  final _tokenCtl = TextEditingController();
  final _sshPathCtl = TextEditingController();
  bool _save = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: widget.host == 'github.com' ? 3 : 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final isGitHub = widget.host == 'github.com';
    return Dialog(
      backgroundColor: const Color(0xFF1F1F23),
      child: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Authentication required for ${widget.host}',
                  style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            TabBar(controller: _tabs, tabs: [
              const Tab(text: 'HTTPS Token'),
              const Tab(text: 'SSH Key'),
              if (isGitHub) const Tab(text: 'GitHub Login'),
            ]),
            SizedBox(
              height: 240,
              child: TabBarView(controller: _tabs, children: [
                _httpsTab(),
                _sshTab(),
                if (isGitHub) _githubTab(),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Checkbox(value: _save, onChanged: (v) => setState(() => _save = v ?? true)),
                const Text('Save for this host', style: TextStyle(color: Color(0xFFB8B8BC))),
                const Spacer(),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _onSubmit, child: const Text('Connect')),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _httpsTab() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: _userCtl, decoration: const InputDecoration(labelText: 'Username')),
          const SizedBox(height: 12),
          TextField(controller: _tokenCtl, obscureText: true, decoration: const InputDecoration(labelText: 'Personal Access Token')),
        ]),
      );

  Widget _sshTab() => Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(controller: _sshPathCtl, decoration: const InputDecoration(labelText: 'Path to private key (e.g. ~/.ssh/id_ed25519)')),
      );

  Widget _githubTab() => const Padding(
        padding: EdgeInsets.all(16),
        child: Text('GitHub Device Flow login (wired in Sub-slice 2C).',
            style: TextStyle(color: Color(0xFFB8B8BC))),
      );

  Future<void> _onSubmit() async {
    AuthSpec? spec;
    if (_tabs.index == 0) {
      if (_userCtl.text.isEmpty || _tokenCtl.text.isEmpty) return;
      spec = AuthHttpsPat(username: _userCtl.text, token: _tokenCtl.text);
    } else if (_tabs.index == 1) {
      if (_sshPathCtl.text.isEmpty) return;
      spec = AuthSsh(privateKeyPath: _sshPathCtl.text);
    } else {
      // GitHub tab — wired in 2C
      return;
    }
    if (_save) await ref.read(credentialsStoreProvider).put(widget.host, spec);
    if (mounted) Navigator.pop(context, spec);
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(ui): AuthDialog with HTTPS/SSH tabs + GitHub placeholder"
```

---

## Sub-slice 2B — Daily writes

### Task B1: stageFiles + unstageFiles (TDD)

**Files:**
- Create: `test/infrastructure/git/git_cli_write_operations_stage_test.dart`
- Modify: `lib/infrastructure/git/git_cli_write_operations.dart`

- [ ] **Step 1: Failing tests**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) => RepoLocation(RepoId.newId(), f.path, 'test');

  group('stageFiles', () {
    test('stages a modified file', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        File(p.join(f.path, 'file_0.txt')).writeAsStringSync('changed');
        final sut = GitCliWriteOperations();
        final res = await sut.stageFiles(loc(f), ['file_0.txt']);
        expect(res, isA<GitSuccess>());
        final status = await Process.run('git', ['status', '--porcelain'], workingDirectory: f.path);
        expect(status.stdout.toString(), contains('M  file_0.txt'));
      } finally { await f.dispose(); }
    });

    test('unstages a staged file', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        File(p.join(f.path, 'file_0.txt')).writeAsStringSync('changed');
        await Process.run('git', ['add', 'file_0.txt'], workingDirectory: f.path);
        final sut = GitCliWriteOperations();
        final res = await sut.unstageFiles(loc(f), ['file_0.txt']);
        expect(res, isA<GitSuccess>());
      } finally { await f.dispose(); }
    });
  });
}
```

- [ ] **Step 2: Implement** — replace the two stub methods in `git_cli_write_operations.dart`:

```dart
@override
Future<GitResult<void>> stageFiles(RepoLocation r, List<String> paths) async {
  if (paths.isEmpty) return const GitSuccess(null);
  try {
    await _runner.run(r.path, ['add', '--', ...paths]);
    return const GitSuccess(null);
  } on GitProcessException catch (e) {
    return GitFailure(_classify(e), e.stderr, e.stderr);
  }
}

@override
Future<GitResult<void>> unstageFiles(RepoLocation r, List<String> paths) async {
  if (paths.isEmpty) return const GitSuccess(null);
  try {
    await _runner.run(r.path, ['restore', '--staged', '--', ...paths]);
    return const GitSuccess(null);
  } on GitProcessException catch (e) {
    return GitFailure(_classify(e), e.stderr, e.stderr);
  }
}

GitErrorKind _classify(GitProcessException e) {
  final s = e.stderr.toLowerCase();
  if (s.contains('auth') || s.contains('401') || s.contains('permission denied')) return GitErrorKind.auth;
  if (s.contains('network') || s.contains('could not resolve') || s.contains('connection')) return GitErrorKind.network;
  if (s.contains('non-fast-forward') || s.contains('rejected')) return GitErrorKind.nonFastForward;
  if (s.contains('conflict')) return GitErrorKind.conflict;
  if (s.contains('would be overwritten')) return GitErrorKind.dirtyWorkingTree;
  if (s.contains('unknown revision') || s.contains('not a valid ref')) return GitErrorKind.unknownRef;
  return GitErrorKind.other;
}
```

(Import `GitProcessException` from `git_process_runner.dart` if not already.)

- [ ] **Step 3: Run + commit**

```bash
& 'C:\src\flutter\bin\flutter.bat' test test/infrastructure/git/git_cli_write_operations_stage_test.dart
git add lib test
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(infra): stageFiles + unstageFiles via git add/restore (TDD)"
```

---

### Task B2: stagePatch + unstagePatch via git apply

**Files:**
- Modify: `lib/infrastructure/git/git_cli_write_operations.dart`
- Modify: `lib/infrastructure/git/git_process_runner.dart` (add stdin variant)
- Create: `test/infrastructure/git/git_cli_write_operations_patch_test.dart`

- [ ] **Step 1: Add `runWithStdin` to `git_process_runner.dart`**

```dart
Future<String> runWithStdin(String workingDir, List<String> args, String input) async {
  final p = await Process.start(executable, args, workingDirectory: workingDir);
  p.stdin.add(utf8.encode(input));
  await p.stdin.close();
  final outBuf = StringBuffer();
  final errBuf = StringBuffer();
  await Future.wait([
    p.stdout.transform(utf8.decoder).forEach(outBuf.write),
    p.stderr.transform(utf8.decoder).forEach(errBuf.write),
  ]);
  final exit = await p.exitCode;
  if (exit != 0) throw GitProcessException(args, exit, errBuf.toString());
  return outBuf.toString();
}
```

- [ ] **Step 2: Failing test**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  test('stagePatch applies a unified diff', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      // Modify file_0.txt: original is "content 0\n"
      File(p.join(f.path, 'file_0.txt')).writeAsStringSync('content 0\nnew line\n');
      final patch = '''diff --git a/file_0.txt b/file_0.txt
--- a/file_0.txt
+++ b/file_0.txt
@@ -1 +1,2 @@
 content 0
+new line
''';
      final sut = GitCliWriteOperations();
      final res = await sut.stagePatch(RepoLocation(RepoId.newId(), f.path, 't'), patch);
      expect(res, isA<GitSuccess>());
      final status = await Process.run('git', ['diff', '--cached', '--name-only'], workingDirectory: f.path);
      expect(status.stdout.toString(), contains('file_0.txt'));
    } finally { await f.dispose(); }
  });
}
```

- [ ] **Step 3: Implement**

```dart
@override
Future<GitResult<void>> stagePatch(RepoLocation r, String unifiedDiff) async {
  try {
    await _runner.runWithStdin(r.path, ['apply', '--cached', '--whitespace=nowarn', '-'], unifiedDiff);
    return const GitSuccess(null);
  } on GitProcessException catch (e) {
    return GitFailure(_classify(e), e.stderr, e.stderr);
  }
}

@override
Future<GitResult<void>> unstagePatch(RepoLocation r, String unifiedDiff) async {
  try {
    await _runner.runWithStdin(r.path, ['apply', '--cached', '--reverse', '--whitespace=nowarn', '-'], unifiedDiff);
    return const GitSuccess(null);
  } on GitProcessException catch (e) {
    return GitFailure(_classify(e), e.stderr, e.stderr);
  }
}
```

- [ ] **Step 4: Commit**

```bash
git add lib test
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(infra): stagePatch / unstagePatch via git apply --cached (TDD)"
```

---

### Task B3: commit (TDD)

**Files:**
- Create: `test/infrastructure/git/git_cli_write_operations_commit_test.dart`
- Modify: `lib/infrastructure/git/git_cli_write_operations.dart`

- [ ] **Step 1: Failing tests**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/commit_request.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  group('commit', () {
    test('creates a commit with a message', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        File(p.join(f.path, 'new.txt')).writeAsStringSync('hi');
        await Process.run('git', ['add', 'new.txt'], workingDirectory: f.path);
        final sut = GitCliWriteOperations();
        final res = await sut.commit(RepoLocation(RepoId.newId(), f.path, 't'),
            const CommitRequest(message: 'add new'));
        expect(res, isA<GitSuccess>());
        final log = await Process.run('git', ['log', '-1', '--format=%s'], workingDirectory: f.path);
        expect(log.stdout.toString().trim(), 'add new');
      } finally { await f.dispose(); }
    });

    test('amend rewrites the last commit', () async {
      final f = await RepoFixture.withLinearHistory(2);
      try {
        final sut = GitCliWriteOperations();
        final res = await sut.commit(RepoLocation(RepoId.newId(), f.path, 't'),
            const CommitRequest(message: 'amended', amend: true));
        expect(res, isA<GitSuccess>());
        final log = await Process.run('git', ['log', '-1', '--format=%s'], workingDirectory: f.path);
        expect(log.stdout.toString().trim(), 'amended');
      } finally { await f.dispose(); }
    });

    test('sign-off appends Signed-off-by trailer', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        File(p.join(f.path, 'new.txt')).writeAsStringSync('hi');
        await Process.run('git', ['add', 'new.txt'], workingDirectory: f.path);
        final sut = GitCliWriteOperations();
        final res = await sut.commit(RepoLocation(RepoId.newId(), f.path, 't'),
            const CommitRequest(message: 'signed', signOff: true));
        expect(res, isA<GitSuccess>());
        final body = await Process.run('git', ['log', '-1', '--format=%B'], workingDirectory: f.path);
        expect(body.stdout.toString(), contains('Signed-off-by'));
      } finally { await f.dispose(); }
    });
  });
}
```

- [ ] **Step 2: Implement**

```dart
@override
Future<GitResult<CommitSha>> commit(RepoLocation r, CommitRequest req) async {
  final args = <String>['commit', '-m', req.message];
  if (req.amend) args.add('--amend');
  if (req.signOff) args.add('--signoff');
  if (req.authorName != null && req.authorEmail != null) {
    args.addAll(['--author', '${req.authorName} <${req.authorEmail}>']);
  }
  // Allow empty commits only on amend (to update msg of last commit)
  if (req.amend) args.add('--allow-empty');
  try {
    await _runner.run(r.path, args);
    final sha = (await _runner.run(r.path, ['rev-parse', 'HEAD'])).trim();
    return GitSuccess(CommitSha(sha));
  } on GitProcessException catch (e) {
    return GitFailure(_classify(e), e.stderr, e.stderr);
  }
}
```

Make sure to import `CommitRequest`, `CommitSha`.

- [ ] **Step 3: Commit**

```bash
git add lib test
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(infra): commit with amend/sign-off (TDD)"
```

---

### Task B4: Branch CRUD (TDD)

**Files:**
- Create: `test/infrastructure/git/git_cli_write_operations_branch_test.dart`
- Modify: `lib/infrastructure/git/git_cli_write_operations.dart`

- [ ] **Step 1: Failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'dart:io';
import '../../_helpers/repo_fixture.dart';

void main() {
  RepoLocation loc(RepoFixture f) => RepoLocation(RepoId.newId(), f.path, 't');

  group('branch ops', () {
    test('createBranch from HEAD', () async {
      final f = await RepoFixture.withLinearHistory(1);
      try {
        final sut = GitCliWriteOperations();
        final res = await sut.createBranch(loc(f), 'feature/x');
        expect(res, isA<GitSuccess>());
        final out = await Process.run('git', ['branch', '--list'], workingDirectory: f.path);
        expect(out.stdout.toString(), contains('feature/x'));
      } finally { await f.dispose(); }
    });

    test('checkout switches HEAD', () async {
      final f = await RepoFixture.withBranches();
      try {
        final sut = GitCliWriteOperations();
        final res = await sut.checkout(loc(f), 'feature');
        expect(res, isA<GitSuccess>());
        final out = await Process.run('git', ['rev-parse', '--abbrev-ref', 'HEAD'], workingDirectory: f.path);
        expect(out.stdout.toString().trim(), 'feature');
      } finally { await f.dispose(); }
    });

    test('deleteBranch removes a non-current branch', () async {
      final f = await RepoFixture.withBranches();
      try {
        final sut = GitCliWriteOperations();
        await sut.checkout(loc(f), 'master');
        final res = await sut.deleteBranch(loc(f), 'feature', force: true);
        expect(res, isA<GitSuccess>());
      } finally { await f.dispose(); }
    });

    test('renameBranch', () async {
      final f = await RepoFixture.withBranches();
      try {
        final sut = GitCliWriteOperations();
        final res = await sut.renameBranch(loc(f), 'feature', 'feature-renamed');
        expect(res, isA<GitSuccess>());
      } finally { await f.dispose(); }
    });
  });
}
```

- [ ] **Step 2: Implement (5 methods)**

```dart
@override
Future<GitResult<void>> createBranch(RepoLocation r, String name, {CommitSha? at, bool checkout = false}) async {
  try {
    final args = checkout ? ['checkout', '-b', name] : ['branch', name];
    if (at != null) args.add(at.value);
    await _runner.run(r.path, args);
    return const GitSuccess(null);
  } on GitProcessException catch (e) {
    return GitFailure(_classify(e), e.stderr, e.stderr);
  }
}

@override
Future<GitResult<void>> checkout(RepoLocation r, String ref, {bool force = false}) async {
  try {
    final args = <String>['checkout'];
    if (force) args.add('--force');
    args.add(ref);
    await _runner.run(r.path, args);
    return const GitSuccess(null);
  } on GitProcessException catch (e) {
    return GitFailure(_classify(e), e.stderr, e.stderr);
  }
}

@override
Future<GitResult<void>> deleteBranch(RepoLocation r, String name, {bool force = false, bool remote = false}) async {
  try {
    if (remote) {
      // Delete remote branch via push --delete
      final parts = name.split('/');
      if (parts.length < 2) {
        return const GitFailure(GitErrorKind.invalidArgument, 'remote branch name must be <remote>/<branch>');
      }
      final remoteName = parts.first;
      final branchName = parts.sublist(1).join('/');
      await _runner.run(r.path, ['push', remoteName, '--delete', branchName]);
    } else {
      final flag = force ? '-D' : '-d';
      await _runner.run(r.path, ['branch', flag, name]);
    }
    return const GitSuccess(null);
  } on GitProcessException catch (e) {
    return GitFailure(_classify(e), e.stderr, e.stderr);
  }
}

@override
Future<GitResult<void>> renameBranch(RepoLocation r, String oldName, String newName) async {
  try {
    await _runner.run(r.path, ['branch', '-m', oldName, newName]);
    return const GitSuccess(null);
  } on GitProcessException catch (e) {
    return GitFailure(_classify(e), e.stderr, e.stderr);
  }
}

@override
Future<GitResult<void>> setUpstream(RepoLocation r, String branch, String upstream) async {
  try {
    await _runner.run(r.path, ['branch', '--set-upstream-to=$upstream', branch]);
    return const GitSuccess(null);
  } on GitProcessException catch (e) {
    return GitFailure(_classify(e), e.stderr, e.stderr);
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib test
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(infra): branch CRUD + checkout + setUpstream (TDD)"
```

---

### Task B5: createTag / deleteTag / discardChanges

**Files:**
- Create: `test/infrastructure/git/git_cli_write_operations_tag_test.dart`
- Modify: `lib/infrastructure/git/git_cli_write_operations.dart`

- [ ] **Step 1: Tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'dart:io';
import '../../_helpers/repo_fixture.dart';

void main() {
  test('createTag', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      final sut = GitCliWriteOperations();
      final res = await sut.createTag(RepoLocation(RepoId.newId(), f.path, 't'), 'v1.0');
      expect(res, isA<GitSuccess>());
      final out = await Process.run('git', ['tag', '--list'], workingDirectory: f.path);
      expect(out.stdout.toString(), contains('v1.0'));
    } finally { await f.dispose(); }
  });

  test('deleteTag', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      await Process.run('git', ['tag', 'v0.1'], workingDirectory: f.path);
      final sut = GitCliWriteOperations();
      final res = await sut.deleteTag(RepoLocation(RepoId.newId(), f.path, 't'), 'v0.1');
      expect(res, isA<GitSuccess>());
    } finally { await f.dispose(); }
  });
}
```

- [ ] **Step 2: Implement**

```dart
@override
Future<GitResult<void>> createTag(RepoLocation r, String name, {CommitSha? at, String? message}) async {
  try {
    final args = <String>['tag'];
    if (message != null) args.addAll(['-a', '-m', message]);
    args.add(name);
    if (at != null) args.add(at.value);
    await _runner.run(r.path, args);
    return const GitSuccess(null);
  } on GitProcessException catch (e) {
    return GitFailure(_classify(e), e.stderr, e.stderr);
  }
}

@override
Future<GitResult<void>> deleteTag(RepoLocation r, String name) async {
  try {
    await _runner.run(r.path, ['tag', '-d', name]);
    return const GitSuccess(null);
  } on GitProcessException catch (e) {
    return GitFailure(_classify(e), e.stderr, e.stderr);
  }
}

@override
Future<GitResult<void>> discardChanges(RepoLocation r, List<String> paths) async {
  if (paths.isEmpty) return const GitSuccess(null);
  try {
    await _runner.run(r.path, ['checkout', '--', ...paths]);
    return const GitSuccess(null);
  } on GitProcessException catch (e) {
    return GitFailure(_classify(e), e.stderr, e.stderr);
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib test
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(infra): createTag / deleteTag / discardChanges (TDD)"
```

---

### Task B6: Local Changes pseudo-row in commit graph

**Files:**
- Modify: `lib/ui/commit_graph/commit_graph_panel.dart`
- Create: `lib/ui/commit_graph/local_changes_row.dart`
- Modify: `lib/application/active_workspace_provider.dart` — add `localChangesSelectedProvider`

- [ ] **Step 1: Add provider** in `active_workspace_provider.dart`:

```dart
final localChangesSelectedProvider = StateProvider<bool>((_) => false);
```

- [ ] **Step 2: LocalChangesRow widget**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/providers.dart';
import '../../domain/repositories/repo_location.dart';

final repoStatusProvider = FutureProvider.family.autoDispose((ref, RepoLocation r) async {
  final git = ref.watch(gitReadOperationsProvider);
  return git.getStatus(r);
});

class LocalChangesRow extends ConsumerWidget {
  final RepoLocation repo;
  const LocalChangesRow({super.key, required this.repo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(repoStatusProvider(repo));
    final selected = ref.watch(localChangesSelectedProvider);
    return async.when(
      data: (status) {
        if (status.entries.isEmpty) return const SizedBox.shrink();
        final count = status.entries.length;
        return Material(
          color: selected ? const Color(0xFF094771) : Colors.transparent,
          child: InkWell(
            onTap: () {
              ref.read(localChangesSelectedProvider.notifier).state = true;
              ref.read(selectedCommitShaProvider.notifier).state = null;
            },
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                const Icon(Icons.edit_note, size: 16, color: Color(0xFFD7BA7D)),
                const SizedBox(width: 8),
                Text('Local Changes ($count)',
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFD7BA7D),
                      fontSize: 12.5, fontWeight: FontWeight.w600,
                    )),
              ]),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
```

- [ ] **Step 3: Insert into CommitGraphPanel** — wrap the existing ListView.builder in a Column with the row on top:

In `commit_graph_panel.dart`, in the `data` builder:

```dart
return Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    LocalChangesRow(repo: repo),
    Expanded(child: ListView.builder( /* existing */ )),
  ],
);
```

Add import: `import 'local_changes_row.dart';`

- [ ] **Step 4: Commit**

```bash
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(ui): Local Changes pseudo-row at top of commit graph"
```

---

### Task B7: Working Copy panel — skeleton + file list

**Files:**
- Create: `lib/ui/working_copy/working_copy_panel.dart`
- Modify: `lib/main.dart` — route bottom panel to WorkingCopyPanel when `localChangesSelectedProvider` is true

- [ ] **Step 1: Panel skeleton**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../domain/repositories/repo_location.dart';
import '../../domain/status/working_file_entry.dart';
import 'commit_compose.dart';

final _workingCopyStatusProvider =
    FutureProvider.family.autoDispose<List<WorkingFileEntry>, RepoLocation>((ref, repo) async {
  final git = ref.watch(gitReadOperationsProvider);
  final status = await git.getStatus(repo);
  return status.entries;
});

class WorkingCopyPanel extends ConsumerWidget {
  final RepoLocation repo;
  const WorkingCopyPanel({super.key, required this.repo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_workingCopyStatusProvider(repo));
    return Container(
      color: const Color(0xFF1F1F23),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Color(0xFFC4314B)))),
        data: (entries) {
          final unstaged = entries.where((e) =>
              e.workingTreeState != WorkingFileState.unmodified).toList();
          final staged = entries.where((e) =>
              e.indexState != WorkingFileState.unmodified).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _FileList(
                repo: repo, unstaged: unstaged, staged: staged,
              )),
              const Divider(height: 1, color: Color(0xFF313137)),
              CommitCompose(repo: repo),
            ],
          );
        },
      ),
    );
  }
}

class _FileList extends ConsumerWidget {
  final RepoLocation repo;
  final List<WorkingFileEntry> unstaged;
  final List<WorkingFileEntry> staged;
  const _FileList({required this.repo, required this.unstaged, required this.staged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(children: [
      _Header(
        title: 'Unstaged (${unstaged.length})',
        action: 'Stage all',
        onAction: unstaged.isEmpty ? null : () async {
          await ref.read(gitWriteOperationsProvider).stageFiles(repo, unstaged.map((e) => e.path).toList());
          ref.invalidate(_workingCopyStatusProvider(repo));
        },
      ),
      for (final e in unstaged) _FileRow(repo: repo, entry: e, isStaged: false),
      _Header(
        title: 'Staged (${staged.length})',
        action: 'Unstage all',
        onAction: staged.isEmpty ? null : () async {
          await ref.read(gitWriteOperationsProvider).unstageFiles(repo, staged.map((e) => e.path).toList());
          ref.invalidate(_workingCopyStatusProvider(repo));
        },
      ),
      for (final e in staged) _FileRow(repo: repo, entry: e, isStaged: true),
    ]);
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const _Header({required this.title, this.action, this.onAction});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF25252A),
      child: Row(children: [
        Text(title, style: const TextStyle(color: Color(0xFFB8B8BC), fontSize: 11.5, fontWeight: FontWeight.w600)),
        const Spacer(),
        if (action != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ]),
    );
  }
}

class _FileRow extends ConsumerWidget {
  final RepoLocation repo;
  final WorkingFileEntry entry;
  final bool isStaged;
  const _FileRow({required this.repo, required this.entry, required this.isStaged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final write = ref.read(gitWriteOperationsProvider);
    return InkWell(
      onTap: () async {
        if (isStaged) {
          await write.unstageFiles(repo, [entry.path]);
        } else {
          await write.stageFiles(repo, [entry.path]);
        }
        ref.invalidate(_workingCopyStatusProvider(repo));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          Icon(isStaged ? Icons.check_box : Icons.check_box_outline_blank,
              size: 14, color: const Color(0xFFB8B8BC)),
          const SizedBox(width: 8),
          _StateBadge(state: isStaged ? entry.indexState : entry.workingTreeState),
          const SizedBox(width: 8),
          Expanded(child: Text(entry.path,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 12.5))),
        ]),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  final WorkingFileState state;
  const _StateBadge({required this.state});
  @override
  Widget build(BuildContext context) {
    final (label, color) = _info(state);
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(3),
          border: Border.all(color: color.withValues(alpha: 0.5))),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600)),
    );
  }
  (String, Color) _info(WorkingFileState s) {
    switch (s) {
      case WorkingFileState.added: return ('A', const Color(0xFF4EC9B0));
      case WorkingFileState.modified: return ('M', const Color(0xFFD7BA7D));
      case WorkingFileState.deleted: return ('D', const Color(0xFFC4314B));
      case WorkingFileState.renamed: return ('R', const Color(0xFF6FA8DC));
      case WorkingFileState.untracked: return ('?', const Color(0xFF888892));
      case WorkingFileState.conflicted: return ('U', const Color(0xFFF48771));
      case WorkingFileState.ignored: return ('I', const Color(0xFF5D5D65));
      default: return ('', Colors.transparent);
    }
  }
}
```

- [ ] **Step 2: CommitCompose** at `lib/ui/working_copy/commit_compose.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/git/commit_request.dart';
import '../../application/git/git_result.dart';
import '../../application/providers.dart';
import '../../domain/repositories/repo_location.dart';

class CommitCompose extends ConsumerStatefulWidget {
  final RepoLocation repo;
  const CommitCompose({super.key, required this.repo});
  @override
  ConsumerState<CommitCompose> createState() => _CommitComposeState();
}

class _CommitComposeState extends ConsumerState<CommitCompose> {
  final _ctl = TextEditingController();
  bool _amend = false;
  bool _signOff = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF25252A),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _ctl,
          maxLines: 4, minLines: 2,
          decoration: const InputDecoration(hintText: 'Commit message', filled: true, fillColor: Color(0xFF1F1F23)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Checkbox(value: _amend, onChanged: (v) => setState(() => _amend = v ?? false)),
          const Text('Amend last commit', style: TextStyle(color: Color(0xFFB8B8BC), fontSize: 12)),
          const SizedBox(width: 16),
          Checkbox(value: _signOff, onChanged: (v) => setState(() => _signOff = v ?? false)),
          const Text('Sign off', style: TextStyle(color: Color(0xFFB8B8BC), fontSize: 12)),
          const Spacer(),
          ElevatedButton(onPressed: _busy ? null : _commit, child: const Text('Commit')),
        ]),
      ]),
    );
  }

  Future<void> _commit() async {
    if (_ctl.text.trim().isEmpty && !_amend) return;
    setState(() => _busy = true);
    final res = await ref.read(gitWriteOperationsProvider).commit(
      widget.repo,
      CommitRequest(message: _ctl.text.trim(), amend: _amend, signOff: _signOff),
    );
    setState(() => _busy = false);
    if (res is GitSuccess) {
      _ctl.clear();
      setState(() { _amend = false; _signOff = false; });
      ref.invalidate(gitReadOperationsProvider); // forces refresh
    } else if (res is GitFailure) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Commit failed: ${res.message}')));
    }
  }
}
```

- [ ] **Step 3: Route bottom panel in `main.dart`** — when `localChangesSelectedProvider` is true, show WorkingCopyPanel instead of BottomPanel:

```dart
// in Shell.build, replace the BottomPanel widget:
final localChanges = ref.watch(localChangesSelectedProvider);
// ...
SizedBox(
  height: 320,
  child: localChanges
      ? WorkingCopyPanel(repo: active.location)
      : BottomPanel(repo: active.location),
),
```

Add imports. Also reset `localChangesSelectedProvider` to false whenever the user clicks any commit row.

- [ ] **Step 4: Build + commit**

```bash
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(ui): Working Copy panel with file-level stage/unstage + commit compose"
```

---

### Task B8: Working Copy hunk expansion + selective staging

**Files:**
- Modify: `lib/ui/working_copy/working_copy_panel.dart`

- [ ] **Step 1: Add hunk expansion state**

For each file, lazily fetch `getDiff` via the existing `gitReadOperationsProvider` and render hunks below the file row when expanded. Wire a Set<HunkId> of selected hunks per file. Track "stage selected hunks" button. When clicked, build a unified diff containing only the selected hunks and call `stagePatch`.

(This task's full code is ~200 lines; the structure follows the spec §4.2. The implementer should use the existing diff parser output: per-file hunks with their original header line, plus the lines. Construct the patch text by concatenating `diff --git`, `index`, `--- a/x`, `+++ b/x`, and the selected hunks' headers + lines.)

The patch construction helper:

```dart
String buildPatchForHunks(String filePath, List<DiffHunk> hunks) {
  final buf = StringBuffer();
  buf.writeln('diff --git a/$filePath b/$filePath');
  buf.writeln('--- a/$filePath');
  buf.writeln('+++ b/$filePath');
  for (final h in hunks) {
    buf.writeln(h.header);
    for (final line in h.lines) {
      switch (line.kind) {
        case DiffLineKind.addition: buf.writeln('+${line.content}'); break;
        case DiffLineKind.deletion: buf.writeln('-${line.content}'); break;
        case DiffLineKind.context: buf.writeln(' ${line.content}'); break;
      }
    }
  }
  return buf.toString();
}
```

Wire a "Stage selected hunks" button per expanded file. When clicked:
```dart
final patch = buildPatchForHunks(entry.path, selectedHunksForFile);
final res = await ref.read(gitWriteOperationsProvider).stagePatch(repo, patch);
```

- [ ] **Step 2: Commit**

```bash
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(ui): Working Copy hunk-level staging via git apply --cached"
```

---

### Task B9: Branch ops dialogs

**Files:**
- Create: `lib/ui/dialogs/branch_create_dialog.dart`
- Create: `lib/ui/dialogs/confirm_dialog.dart`

- [ ] **Step 1: branch_create_dialog.dart**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../domain/commits/commit_sha.dart';
import '../../domain/repositories/repo_location.dart';

class BranchCreateDialog extends ConsumerStatefulWidget {
  final RepoLocation repo;
  final CommitSha? at;
  const BranchCreateDialog({super.key, required this.repo, this.at});

  static Future<bool> show(BuildContext context, RepoLocation r, {CommitSha? at}) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => BranchCreateDialog(repo: r, at: at));
    return ok ?? false;
  }

  @override
  ConsumerState<BranchCreateDialog> createState() => _State();
}

class _State extends ConsumerState<BranchCreateDialog> {
  final _ctl = TextEditingController();
  bool _checkout = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New branch'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _ctl, autofocus: true, decoration: const InputDecoration(labelText: 'Branch name')),
        const SizedBox(height: 8),
        if (widget.at != null) Text('From: ${widget.at!.short()}', style: const TextStyle(color: Color(0xFF888892))),
        Row(children: [
          Checkbox(value: _checkout, onChanged: (v) => setState(() => _checkout = v ?? true)),
          const Text('Switch to this branch'),
        ]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(onPressed: _create, child: const Text('Create')),
      ],
    );
  }

  Future<void> _create() async {
    if (_ctl.text.trim().isEmpty) return;
    final write = ref.read(gitWriteOperationsProvider);
    await write.createBranch(widget.repo, _ctl.text.trim(), at: widget.at, checkout: _checkout);
    if (mounted) Navigator.pop(context, true);
  }
}
```

- [ ] **Step 2: confirm_dialog.dart**

```dart
import 'package:flutter/material.dart';

class ConfirmDialog extends StatelessWidget {
  final String title;
  final String body;
  final String? confirmLabel;
  final bool dangerous;
  const ConfirmDialog({super.key, required this.title, required this.body, this.confirmLabel, this.dangerous = false});

  static Future<bool> show(BuildContext context, {required String title, required String body, String? confirmLabel, bool dangerous = false}) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => ConfirmDialog(title: title, body: body, confirmLabel: confirmLabel, dangerous: dangerous));
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          style: dangerous ? ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC4314B)) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel ?? 'OK'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(ui): branch create dialog + reusable confirm dialog"
```

---

### Task B10: Sidebar context menu for branches

**Files:**
- Modify: `lib/ui/sidebar/sidebar.dart` — wrap each branch row in GestureDetector for right-click

- [ ] **Step 1: Add `onSecondaryTapDown` to the leaf-row InkWell**

When invoked, show a `PopupMenu` with: Checkout / Merge into current / Rename… / Delete / Set upstream… / Push to <remote>.

Use `showMenu` from Material:

```dart
onSecondaryTapDown: (details) async {
  final selected = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(details.globalPosition.dx, details.globalPosition.dy, details.globalPosition.dx, details.globalPosition.dy),
    items: const [
      PopupMenuItem(value: 'checkout', child: Text('Checkout')),
      PopupMenuItem(value: 'merge', child: Text('Merge into current')),
      PopupMenuItem(value: 'rename', child: Text('Rename…')),
      PopupMenuItem(value: 'delete', child: Text('Delete')),
      PopupMenuItem(value: 'upstream', child: Text('Set upstream…')),
    ],
  );
  // dispatch by `selected`
},
```

Implement each action by calling the appropriate `gitWriteOperationsProvider` method. For `delete`, show ConfirmDialog first.

- [ ] **Step 2: Commit**

```bash
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(ui): right-click context menu on sidebar branches"
```

---

## Sub-slice 2C — Sync ops

### Task C1: fetch (TDD with local file:// remote)

**Files:**
- Modify: `test/_helpers/repo_fixture.dart` — add `withFileRemote()`
- Create: `test/infrastructure/git/git_cli_write_operations_fetch_test.dart`
- Modify: `lib/infrastructure/git/git_cli_write_operations.dart`

- [ ] **Step 1: Fixture extension**

Add to `RepoFixture`:
```dart
static Future<RepoFixture> withFileRemote() async {
  final origin = await withLinearHistory(3);
  final local = await empty();
  await _git(local.path, ['remote', 'add', 'origin', origin.path]);
  return local;
}
```

- [ ] **Step 2: Failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_progress.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import '../../_helpers/repo_fixture.dart';

void main() {
  test('fetch from local file:// remote emits progress and succeeds', () async {
    final origin = await RepoFixture.withLinearHistory(3);
    final local = await RepoFixture.empty();
    try {
      await Process.run('git', ['remote', 'add', 'origin', origin.path], workingDirectory: local.path);
      final sut = GitCliWriteOperations();
      final loc = RepoLocation(RepoId.newId(), local.path, 't');
      final events = <GitProgress>[];
      await for (final e in sut.fetch(loc, remote: 'origin')) {
        events.add(e);
      }
      // Even if no progress lines emit on local-fs remote, the stream must complete cleanly.
      // Verify the fetch worked:
      final refs = await Process.run('git', ['branch', '-r'], workingDirectory: local.path);
      expect(refs.stdout.toString(), contains('origin/'));
    } finally {
      await origin.dispose();
      await local.dispose();
    }
  });
}
```

(Add the `Process` import to the test.)

- [ ] **Step 3: Implement**

```dart
@override
Stream<GitProgress> fetch(RepoLocation r, {String? remote, bool all = false, AuthSpec? auth}) async* {
  final args = <String>['fetch', '--progress'];
  if (all) args.add('--all');
  else if (remote != null) args.add(remote);
  await for (final p in _runProgressStream(r.path, args, auth: auth)) yield p;
}

Stream<GitProgress> _runProgressStream(String cwd, List<String> args, {AuthSpec? auth}) async* {
  final env = <String, String>{};
  // Apply auth env if specified
  if (auth is AuthSsh) {
    env['GIT_SSH_COMMAND'] = 'ssh -i ${auth.privateKeyPath} -F /dev/null -o IdentitiesOnly=yes';
  }
  // Token-based HTTPS injection deferred to Task C5 (credential helper)
  final p = await Process.start(_runner.executable, args, workingDirectory: cwd, environment: env);
  await for (final line in p.stderr.transform(utf8.decoder).transform(const LineSplitter())) {
    final parsed = GitProgressParser.parse(line);
    if (parsed != null) yield parsed;
  }
  final exit = await p.exitCode;
  if (exit != 0) {
    throw GitProcessException(args, exit, '');
  }
}
```

Note `_runner.executable` and `GitProgressParser` imports.

- [ ] **Step 4: Commit**

```bash
git add lib test
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(infra): fetch with progress stream (TDD)"
```

---

### Task C2: pull + push (TDD)

**Files:**
- Modify: `lib/infrastructure/git/git_cli_write_operations.dart`
- Create: `test/infrastructure/git/git_cli_write_operations_pull_push_test.dart`

- [ ] **Step 1: Tests** — pull from local origin, push to local origin (using bare repo).

```dart
// Set up: create origin (bare clone of seed), local clone, make a commit locally, push.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  test('push to local bare remote succeeds', () async {
    final seed = await RepoFixture.withLinearHistory(1);
    // Create a bare remote
    final bareDir = Directory.systemTemp.createTempSync('gitopen-test-bare-');
    await Process.run('git', ['clone', '--bare', seed.path, bareDir.path]);
    try {
      // Use seed as local; rewire its origin to bare
      await Process.run('git', ['remote', 'add', 'bare', bareDir.path], workingDirectory: seed.path);
      // Add a new commit in seed
      await Process.run('git', ['commit', '--allow-empty', '-m', 'extra'], workingDirectory: seed.path);
      final sut = GitCliWriteOperations();
      final events = await sut.push(
        RepoLocation(RepoId.newId(), seed.path, 't'),
        remote: 'bare',
        branch: 'master',
      ).toList();
      // Verify the bare has the new commit
      final log = await Process.run('git', ['log', '-1', '--format=%s'], workingDirectory: bareDir.path);
      expect(log.stdout.toString().trim(), 'extra');
    } finally {
      await seed.dispose();
      bareDir.deleteSync(recursive: true);
    }
  });
}
```

- [ ] **Step 2: Implement**

```dart
@override
Stream<GitProgress> pull(RepoLocation r, PullStrategy strategy, {AuthSpec? auth}) async* {
  final args = <String>['pull', '--progress'];
  switch (strategy) {
    case PullStrategy.ffOnly: args.add('--ff-only'); break;
    case PullStrategy.merge: args.add('--no-rebase'); break;
    case PullStrategy.rebase: args.add('--rebase'); break;
  }
  await for (final p in _runProgressStream(r.path, args, auth: auth)) yield p;
}

@override
Stream<GitProgress> push(RepoLocation r,
    {String? remote, String? branch, bool forceWithLease = false, bool pushTags = false, AuthSpec? auth}) async* {
  final args = <String>['push', '--progress'];
  if (forceWithLease) args.add('--force-with-lease');
  if (pushTags) args.add('--tags');
  if (remote != null) {
    args.add(remote);
    if (branch != null) args.add(branch);
  }
  await for (final p in _runProgressStream(r.path, args, auth: auth)) yield p;
}
```

- [ ] **Step 3: Commit**

```bash
git add lib test
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(infra): pull + push with progress streams (TDD)"
```

---

### Task C3: Custom credential helper + GIT_ASKPASS

**Files:**
- Create: `lib/infrastructure/git/credential_helper.dart`
- Modify: `lib/infrastructure/git/git_cli_write_operations.dart` — wire env for HTTPS auth

- [ ] **Step 1: Design**

Git's credential helper protocol: when git needs credentials it invokes the helper with `get` action and reads `username=...\npassword=...\n` from stdout. We embed a Dart entry point that reads the host from `protocol` + `host` env input and looks it up in the credentials store.

For simplicity in Slice 2, use `GIT_ASKPASS` instead — it's simpler. Git invokes the script with the prompt as the only arg ("Username for 'https://...': " or "Password for 'https://...': "), and writes the corresponding credential to stdout.

We ship a small batch/sh script (.bat on Windows) that's auto-generated at app startup, pointing to a Dart-side IPC (a local socket or named pipe) where our app responds with the stored credential.

For Slice 2 simplification: write the credential to a temp file, set `GIT_ASKPASS` to a tiny .bat that prints the contents, then delete the temp file after the op.

Implementation:

```dart
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../application/git/auth_spec.dart';

class CredentialHelper {
  /// Returns env vars to set on the git subprocess. Caller MUST call dispose() after.
  static Future<({Map<String, String> env, void Function() dispose})> setup(AuthSpec? auth, String host) async {
    if (auth == null || auth is AuthSystemDefault) {
      return (env: <String, String>{}, dispose: () {});
    }
    if (auth is AuthSsh) {
      return (env: {
        'GIT_SSH_COMMAND': 'ssh -i ${auth.privateKeyPath} -F /dev/null -o IdentitiesOnly=yes',
      }, dispose: () {});
    }
    // HTTPS or OAuth — produce ASKPASS script
    final tmp = Directory.systemTemp.createTempSync('gitopen-askpass-');
    final usrFile = File(p.join(tmp.path, 'user.txt'));
    final pwdFile = File(p.join(tmp.path, 'pass.txt'));
    final scriptFile = File(p.join(tmp.path, Platform.isWindows ? 'askpass.bat' : 'askpass.sh'));

    String username; String secret;
    if (auth is AuthHttpsPat) { username = auth.username; secret = auth.token; }
    else if (auth is AuthHttpsBasic) { username = auth.username; secret = auth.password; }
    else if (auth is AuthGitHubOauth) { username = 'x-access-token'; secret = auth.accessToken; }
    else { return (env: <String, String>{}, dispose: () {}); }

    await usrFile.writeAsString(username);
    await pwdFile.writeAsString(secret);

    if (Platform.isWindows) {
      await scriptFile.writeAsString('''@echo off
echo %1 | findstr /i "ame" >nul && type "${usrFile.path}" || type "${pwdFile.path}"
''');
    } else {
      await scriptFile.writeAsString('''#!/bin/sh
case "\$1" in
  *[Uu]sername*) cat "${usrFile.path}" ;;
  *) cat "${pwdFile.path}" ;;
esac
''');
      await Process.run('chmod', ['+x', scriptFile.path]);
    }

    return (
      env: {
        'GIT_ASKPASS': scriptFile.path,
        'GIT_TERMINAL_PROMPT': '0',
      },
      dispose: () { try { tmp.deleteSync(recursive: true); } catch (_) {} },
    );
  }
}
```

- [ ] **Step 2: Wire into `_runProgressStream`**

```dart
Stream<GitProgress> _runProgressStream(String cwd, List<String> args, {AuthSpec? auth}) async* {
  final helper = await CredentialHelper.setup(auth, '');
  try {
    final p = await Process.start(_runner.executable, args, workingDirectory: cwd, environment: helper.env);
    await for (final line in p.stderr.transform(utf8.decoder).transform(const LineSplitter())) {
      final parsed = GitProgressParser.parse(line);
      if (parsed != null) yield parsed;
    }
    final exit = await p.exitCode;
    if (exit != 0) throw GitProcessException(args, exit, '');
  } finally {
    helper.dispose();
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(infra): credential helper via GIT_ASKPASS for HTTPS auth"
```

---

### Task C4: Toolbar widget — Fetch/Pull/Push buttons

**Files:**
- Create: `lib/ui/toolbar/git_toolbar.dart`
- Modify: `lib/main.dart` — add toolbar between repo selector and window controls

- [ ] **Step 1: GitToolbar widget**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/git/git_write_operations.dart';
import '../../application/operations/operations_notifier.dart';
import '../../application/operations/running_operation.dart';
import '../../application/providers.dart';
import '../../domain/repositories/repo_location.dart';

class GitToolbar extends ConsumerWidget {
  const GitToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeId = ref.watch(activeWorkspaceIdProvider);
    final workspaces = ref.watch(workspaceManagerProvider);
    final active = workspaces.where((w) => w.location.id == activeId).cast<dynamic>().firstOrNull;
    final enabled = active != null;

    return Row(mainAxisSize: MainAxisSize.min, children: [
      _ToolbarButton(icon: Icons.cloud_download, label: 'Fetch', enabled: enabled, onTap: () => _fetch(ref, active!.location)),
      _ToolbarButton(icon: Icons.south, label: 'Pull', enabled: enabled, onTap: () => _pull(ref, active!.location)),
      _ToolbarButton(icon: Icons.north, label: 'Push', enabled: enabled, onTap: () => _push(ref, active!.location)),
    ]);
  }

  Future<void> _fetch(WidgetRef ref, RepoLocation repo) =>
      _runStream(ref, OpKind.fetch, 'Fetching origin', repo,
          ref.read(gitWriteOperationsProvider).fetch(repo));

  Future<void> _pull(WidgetRef ref, RepoLocation repo) =>
      _runStream(ref, OpKind.pull, 'Pulling', repo,
          ref.read(gitWriteOperationsProvider).pull(repo, PullStrategy.merge));

  Future<void> _push(WidgetRef ref, RepoLocation repo) =>
      _runStream(ref, OpKind.push, 'Pushing', repo,
          ref.read(gitWriteOperationsProvider).push(repo));

  Future<void> _runStream(WidgetRef ref, OpKind kind, String label, RepoLocation repo, Stream<dynamic> stream) async {
    final ops = ref.read(operationsProvider.notifier);
    final id = ops.start(kind, label, repo: repo);
    try {
      await for (final ev in stream) {
        final p = ev as dynamic; // GitProgress
        ops.updateProgress(id, p.fraction, p.phase);
      }
      ops.finishSuccess(id);
      ref.invalidate(gitReadOperationsProvider);
    } catch (e) {
      ops.finishFailure(id, e.toString());
    }
  }
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _ToolbarButton({required this.icon, required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(children: [
            Icon(icon, size: 14, color: const Color(0xFFB8B8BC)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Wire into `_TitleBar`** in `main.dart` — between RepoSelector and right MoveWindow spacer:

```dart
Expanded(child: MoveWindow()),
const RepoSelector(),
const SizedBox(width: 8),
const GitToolbar(),
Expanded(child: MoveWindow()),
const _WindowControls(),
```

Add `import 'ui/toolbar/git_toolbar.dart';`.

- [ ] **Step 3: Commit**

```bash
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(ui): Fetch/Pull/Push toolbar buttons wired to operations notifier"
```

---

### Task C5: Auto-prompt AuthDialog on failure

**Files:**
- Modify: `lib/ui/toolbar/git_toolbar.dart` — catch auth failure and open AuthDialog

- [ ] **Step 1: Detect GitErrorKind.auth from stderr in the stream catch**

In `_runStream`:
```dart
try {
  await for (final ev in stream) { /* ... */ }
  ops.finishSuccess(id);
} catch (e) {
  final msg = e.toString();
  if (msg.toLowerCase().contains('auth') || msg.contains('401')) {
    ops.finishFailure(id, 'Authentication required');
    // Trigger AuthDialog. Need a way to get host — parse the remote URL.
    // For simplicity, default to 'github.com' for now; refine in plan revision.
    // Show AuthDialog via context. We need a NavigatorKey or BuildContext — pass it via widget.
  } else {
    ops.finishFailure(id, msg);
  }
}
```

Refactor `GitToolbar` to be a `ConsumerStatefulWidget` so it has a BuildContext for `AuthDialog.show`. After AuthDialog returns a credential, re-run the operation with `auth: <new credential>`.

(Full implementation is ~80 lines; the implementer writes it following the pattern.)

- [ ] **Step 2: Commit**

```bash
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(ui): auto-prompt AuthDialog when sync op fails with auth error"
```

---

### Task C6: GitHub OAuth Device Flow

**Files:**
- Create: `lib/infrastructure/auth/github_device_flow.dart`
- Modify: `lib/ui/dialogs/auth_dialog.dart` — wire the GitHub tab

- [ ] **Step 1: Device Flow client**

```dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class GitHubDeviceFlow {
  // Hard-coded public client_id of the GitOpen OAuth App.
  // (For Slice 2, register a public OAuth App on github.com → copy client_id here.)
  static const _clientId = 'PUT_REAL_CLIENT_ID_HERE';

  static Future<DeviceCodeResponse> requestDeviceCode({String scope = 'repo'}) async {
    final r = await http.post(
      Uri.parse('https://github.com/login/device/code'),
      headers: {'Accept': 'application/json'},
      body: {'client_id': _clientId, 'scope': scope},
    );
    if (r.statusCode != 200) throw HttpException('device/code ${r.statusCode}: ${r.body}');
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    return DeviceCodeResponse(
      deviceCode: m['device_code'],
      userCode: m['user_code'],
      verificationUri: m['verification_uri'],
      expiresIn: Duration(seconds: m['expires_in']),
      interval: Duration(seconds: m['interval']),
    );
  }

  static Future<String> pollForToken(DeviceCodeResponse r) async {
    final deadline = DateTime.now().add(r.expiresIn);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(r.interval);
      final resp = await http.post(
        Uri.parse('https://github.com/login/oauth/access_token'),
        headers: {'Accept': 'application/json'},
        body: {
          'client_id': _clientId,
          'device_code': r.deviceCode,
          'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
        },
      );
      final m = jsonDecode(resp.body) as Map<String, dynamic>;
      if (m['error'] == 'authorization_pending') continue;
      if (m['error'] == 'slow_down') { await Future.delayed(const Duration(seconds: 5)); continue; }
      if (m['error'] != null) throw StateError('device flow: ${m['error']}');
      if (m['access_token'] is String) return m['access_token'] as String;
    }
    throw TimeoutException('Device flow timed out');
  }
}

class DeviceCodeResponse {
  final String deviceCode;
  final String userCode;
  final String verificationUri;
  final Duration expiresIn;
  final Duration interval;
  DeviceCodeResponse({required this.deviceCode, required this.userCode, required this.verificationUri, required this.expiresIn, required this.interval});
}

class HttpException implements Exception {
  final String message;
  HttpException(this.message);
  @override String toString() => message;
}
```

- [ ] **Step 2: Replace the GitHub tab placeholder in `auth_dialog.dart`**

The GitHub tab now: button "Sign in with GitHub". On press:
1. Call `GitHubDeviceFlow.requestDeviceCode()`
2. Show the user code prominently with a copy button
3. Open `verificationUri` in browser via `url_launcher`
4. Start `pollForToken` in background; when it returns, save as `AuthGitHubOauth`

(Full UI ~60 lines; implementer writes it.)

- [ ] **Step 3: Commit**

```bash
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(infra): GitHub OAuth Device Flow + AuthDialog GitHub tab"
```

---

## Sub-slice 2D — Stash + merge + cherry-pick + conflict UI

### Task D1: Stash CRUD (TDD)

**Files:**
- Create: `test/infrastructure/git/git_cli_write_operations_stash_test.dart`
- Modify: `lib/infrastructure/git/git_cli_write_operations.dart`

- [ ] **Step 1: Tests**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  test('stashSave + stashPop', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      File(p.join(f.path, 'file_0.txt')).writeAsStringSync('changed');
      final sut = GitCliWriteOperations();
      final saved = await sut.stashSave(RepoLocation(RepoId.newId(), f.path, 't'), 'my stash');
      expect(saved, isA<GitSuccess>());
      final list = await Process.run('git', ['stash', 'list'], workingDirectory: f.path);
      expect(list.stdout.toString(), contains('my stash'));
      final popped = await sut.stashPop(RepoLocation(RepoId.newId(), f.path, 't'), 0);
      expect(popped, isA<GitSuccess>());
    } finally { await f.dispose(); }
  });
}
```

- [ ] **Step 2: Implement 4 methods**

```dart
@override
Future<GitResult<void>> stashSave(RepoLocation r, String message, {bool includeUntracked = false}) async {
  try {
    final args = <String>['stash', 'push', '-m', message];
    if (includeUntracked) args.add('-u');
    await _runner.run(r.path, args);
    return const GitSuccess(null);
  } on GitProcessException catch (e) {
    return GitFailure(_classify(e), e.stderr, e.stderr);
  }
}

@override
Future<GitResult<void>> stashPop(RepoLocation r, int index) async {
  try { await _runner.run(r.path, ['stash', 'pop', 'stash@{$index}']); return const GitSuccess(null); }
  on GitProcessException catch (e) { return GitFailure(_classify(e), e.stderr, e.stderr); }
}

@override
Future<GitResult<void>> stashApply(RepoLocation r, int index) async {
  try { await _runner.run(r.path, ['stash', 'apply', 'stash@{$index}']); return const GitSuccess(null); }
  on GitProcessException catch (e) { return GitFailure(_classify(e), e.stderr, e.stderr); }
}

@override
Future<GitResult<void>> stashDrop(RepoLocation r, int index) async {
  try { await _runner.run(r.path, ['stash', 'drop', 'stash@{$index}']); return const GitSuccess(null); }
  on GitProcessException catch (e) { return GitFailure(_classify(e), e.stderr, e.stderr); }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib test
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(infra): stash save/pop/apply/drop (TDD)"
```

---

### Task D2: merge with MergeOutcome (TDD)

**Files:**
- Create: `test/infrastructure/git/git_cli_write_operations_merge_test.dart`
- Modify: `lib/infrastructure/git/git_cli_write_operations.dart`

- [ ] **Step 1: Tests for ff, 3-way clean, conflict**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  test('ff merge', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      await Process.run('git', ['checkout', '-b', 'feature'], workingDirectory: f.path);
      File(p.join(f.path, 'new.txt')).writeAsStringSync('hi');
      await Process.run('git', ['add', '.'], workingDirectory: f.path);
      await Process.run('git', ['commit', '-m', 'fea'], workingDirectory: f.path);
      await Process.run('git', ['checkout', 'master'], workingDirectory: f.path);
      final sut = GitCliWriteOperations();
      final res = await sut.merge(RepoLocation(RepoId.newId(), f.path, 't'), 'feature', ffOnly: true);
      expect(res, isA<GitSuccess>());
      expect((res as GitSuccess).value, isA<MergeFastForward>());
    } finally { await f.dispose(); }
  });

  test('3-way merge with conflict reports conflicted paths', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      // create branch and modify file
      await Process.run('git', ['checkout', '-b', 'feature'], workingDirectory: f.path);
      File(p.join(f.path, 'file_0.txt')).writeAsStringSync('branch version\n');
      await Process.run('git', ['commit', '-am', 'branch'], workingDirectory: f.path);
      // back to master, modify same line
      await Process.run('git', ['checkout', 'master'], workingDirectory: f.path);
      File(p.join(f.path, 'file_0.txt')).writeAsStringSync('master version\n');
      await Process.run('git', ['commit', '-am', 'master'], workingDirectory: f.path);
      final sut = GitCliWriteOperations();
      final res = await sut.merge(RepoLocation(RepoId.newId(), f.path, 't'), 'feature');
      expect(res, isA<GitSuccess>());
      final outcome = (res as GitSuccess).value as MergeOutcome;
      expect(outcome, isA<MergeConflict>());
      expect((outcome as MergeConflict).conflictedPaths, contains('file_0.txt'));
    } finally { await f.dispose(); }
  });
}
```

- [ ] **Step 2: Implement**

```dart
@override
Future<GitResult<MergeOutcome>> merge(RepoLocation r, String ref, {bool ffOnly = false, bool noCommit = false}) async {
  final args = <String>['merge'];
  if (ffOnly) args.add('--ff-only');
  if (noCommit) args.add('--no-commit');
  args.add(ref);
  try {
    final stdout = await _runner.run(r.path, args);
    // Determine outcome by inspecting reflog or status
    final ff = stdout.contains('Fast-forward');
    final head = (await _runner.run(r.path, ['rev-parse', 'HEAD'])).trim();
    if (ff) return GitSuccess(MergeFastForward(CommitSha(head)));
    return GitSuccess(MergeMerged(CommitSha(head)));
  } on GitProcessException catch (e) {
    if (e.stderr.contains('CONFLICT') || e.stderr.contains('Automatic merge failed')) {
      // List unmerged files
      final status = await _runner.run(r.path, ['diff', '--name-only', '--diff-filter=U']);
      final conflicted = status.split('\n').where((l) => l.isNotEmpty).toList();
      return GitSuccess(MergeConflict(conflicted));
    }
    return GitFailure(_classify(e), e.stderr, e.stderr);
  }
}

@override
Future<GitResult<void>> mergeAbort(RepoLocation r) async {
  try { await _runner.run(r.path, ['merge', '--abort']); return const GitSuccess(null); }
  on GitProcessException catch (e) { return GitFailure(_classify(e), e.stderr, e.stderr); }
}

@override
Future<GitResult<CommitSha>> mergeContinue(RepoLocation r) async {
  try {
    await _runner.run(r.path, ['merge', '--continue', '--no-edit']);
    final head = (await _runner.run(r.path, ['rev-parse', 'HEAD'])).trim();
    return GitSuccess(CommitSha(head));
  } on GitProcessException catch (e) { return GitFailure(_classify(e), e.stderr, e.stderr); }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib test
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(infra): merge with MergeOutcome variants (TDD)"
```

---

### Task D3: cherry-pick + reset (TDD)

**Files:**
- Modify: `lib/infrastructure/git/git_cli_write_operations.dart`
- Create: `test/infrastructure/git/git_cli_write_operations_cherrypick_reset_test.dart`

- [ ] **Step 1: Tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/git/git_result.dart';
import 'package:gitopen/application/git/git_write_operations.dart';
import 'package:gitopen/application/git/merge_outcome.dart';
import 'package:gitopen/domain/commits/commit_sha.dart';
import 'package:gitopen/domain/repositories/repo_id.dart';
import 'package:gitopen/domain/repositories/repo_location.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  test('cherry-pick applies a commit from another branch', () async {
    final f = await RepoFixture.withLinearHistory(1);
    try {
      await Process.run('git', ['checkout', '-b', 'feature'], workingDirectory: f.path);
      File(p.join(f.path, 'cp.txt')).writeAsStringSync('hi');
      await Process.run('git', ['add', '.'], workingDirectory: f.path);
      await Process.run('git', ['commit', '-m', 'pick me'], workingDirectory: f.path);
      final featSha = (await Process.run('git', ['rev-parse', 'HEAD'], workingDirectory: f.path)).stdout.toString().trim();
      await Process.run('git', ['checkout', 'master'], workingDirectory: f.path);
      final sut = GitCliWriteOperations();
      final res = await sut.cherryPick(RepoLocation(RepoId.newId(), f.path, 't'), CommitSha(featSha));
      expect(res, isA<GitSuccess>());
      expect((res as GitSuccess).value, isA<CherryPickApplied>());
    } finally { await f.dispose(); }
  });

  test('reset --hard moves HEAD', () async {
    final f = await RepoFixture.withLinearHistory(3);
    try {
      final older = (await Process.run('git', ['rev-parse', 'HEAD~2'], workingDirectory: f.path)).stdout.toString().trim();
      final sut = GitCliWriteOperations();
      final res = await sut.reset(RepoLocation(RepoId.newId(), f.path, 't'), CommitSha(older), ResetMode.hard);
      expect(res, isA<GitSuccess>());
    } finally { await f.dispose(); }
  });
}
```

- [ ] **Step 2: Implement (4 methods)**

```dart
@override
Future<GitResult<CherryPickOutcome>> cherryPick(RepoLocation r, CommitSha sha) async {
  try {
    await _runner.run(r.path, ['cherry-pick', sha.value]);
    final head = (await _runner.run(r.path, ['rev-parse', 'HEAD'])).trim();
    return GitSuccess(CherryPickApplied(CommitSha(head)));
  } on GitProcessException catch (e) {
    if (e.stderr.contains('CONFLICT') || e.stderr.contains('after resolving the conflicts')) {
      final status = await _runner.run(r.path, ['diff', '--name-only', '--diff-filter=U']);
      final conflicted = status.split('\n').where((l) => l.isNotEmpty).toList();
      return GitSuccess(CherryPickConflict(conflicted));
    }
    return GitFailure(_classify(e), e.stderr, e.stderr);
  }
}

@override
Future<GitResult<void>> cherryPickAbort(RepoLocation r) async {
  try { await _runner.run(r.path, ['cherry-pick', '--abort']); return const GitSuccess(null); }
  on GitProcessException catch (e) { return GitFailure(_classify(e), e.stderr, e.stderr); }
}

@override
Future<GitResult<CommitSha>> cherryPickContinue(RepoLocation r) async {
  try {
    await _runner.run(r.path, ['cherry-pick', '--continue']);
    final head = (await _runner.run(r.path, ['rev-parse', 'HEAD'])).trim();
    return GitSuccess(CommitSha(head));
  } on GitProcessException catch (e) { return GitFailure(_classify(e), e.stderr, e.stderr); }
}

@override
Future<GitResult<void>> reset(RepoLocation r, CommitSha to, ResetMode mode) async {
  final flag = switch (mode) {
    ResetMode.soft => '--soft',
    ResetMode.mixed => '--mixed',
    ResetMode.hard => '--hard',
  };
  try { await _runner.run(r.path, ['reset', flag, to.value]); return const GitSuccess(null); }
  on GitProcessException catch (e) { return GitFailure(_classify(e), e.stderr, e.stderr); }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib test
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(infra): cherry-pick + reset with mode (TDD)"
```

---

### Task D4: Conflict detection + Conflict Resolution panel

**Files:**
- Create: `lib/application/git/repo_state_provider.dart`
- Create: `lib/ui/conflicts/conflict_resolution_panel.dart`
- Modify: `lib/main.dart` — route bottom panel to ConflictResolutionPanel when in mid-merge state

- [ ] **Step 1: RepoState provider** — probes `.git/MERGE_HEAD` / `.git/CHERRY_PICK_HEAD`

```dart
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../domain/repositories/repo_location.dart';

enum InProgressOp { none, merge, cherryPick, rebase }

final repoStateProvider = FutureProvider.family.autoDispose<InProgressOp, RepoLocation>((ref, repo) async {
  Future<bool> exists(String name) => File(p.join(repo.path, '.git', name)).exists();
  if (await exists('MERGE_HEAD')) return InProgressOp.merge;
  if (await exists('CHERRY_PICK_HEAD')) return InProgressOp.cherryPick;
  if (await exists('REBASE_HEAD')) return InProgressOp.rebase;
  return InProgressOp.none;
});
```

- [ ] **Step 2: ConflictResolutionPanel**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../application/git/git_result.dart';
import '../../application/git/repo_state_provider.dart';
import '../../application/providers.dart';
import '../../domain/repositories/repo_location.dart';
import '../../domain/status/working_file_entry.dart';

final _conflictsProvider = FutureProvider.family.autoDispose<List<String>, RepoLocation>((ref, repo) async {
  final git = ref.watch(gitReadOperationsProvider);
  final status = await git.getStatus(repo);
  return status.entries
      .where((e) => e.workingTreeState == WorkingFileState.conflicted)
      .map((e) => e.path)
      .toList();
});

class ConflictResolutionPanel extends ConsumerWidget {
  final RepoLocation repo;
  const ConflictResolutionPanel({super.key, required this.repo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final opAsync = ref.watch(repoStateProvider(repo));
    final filesAsync = ref.watch(_conflictsProvider(repo));
    return Container(
      color: const Color(0xFF1F1F23),
      child: opAsync.when(
        loading: () => const SizedBox.shrink(),
        error: (e, _) => Center(child: Text('$e')),
        data: (op) => filesAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => Center(child: Text('$e')),
          data: (files) {
            if (op == InProgressOp.none || files.isEmpty) return const SizedBox.shrink();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                color: const Color(0xFF3D2A1A),
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Icon(Icons.warning_amber, color: Color(0xFFD7BA7D), size: 16),
                  const SizedBox(width: 8),
                  Text('${op == InProgressOp.merge ? "Merge" : "Cherry-pick"} in progress — ${files.length} conflict${files.length == 1 ? "" : "s"}',
                      style: const TextStyle(color: Color(0xFFD4D4D4), fontWeight: FontWeight.w600)),
                ]),
              ),
              Expanded(child: ListView(children: [
                for (final path in files)
                  ListTile(
                    leading: const Icon(Icons.error_outline, color: Color(0xFFC4314B), size: 18),
                    title: Text(path, style: const TextStyle(color: Color(0xFFD4D4D4), fontSize: 12.5)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      TextButton(onPressed: () => _openInEditor(repo.path, path), child: const Text('Open')),
                      TextButton(
                        onPressed: () async {
                          await ref.read(gitWriteOperationsProvider).stageFiles(repo, [path]);
                          ref.invalidate(_conflictsProvider(repo));
                        },
                        child: const Text('Mark resolved'),
                      ),
                    ]),
                  ),
              ])),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  OutlinedButton(onPressed: () => _abort(ref, op), child: const Text('Abort')),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: files.isEmpty ? () => _continue(ref, op) : null,
                    child: const Text('Continue'),
                  ),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Future<void> _openInEditor(String repoPath, String filePath) async {
    final url = Uri.file('$repoPath/$filePath');
    await launchUrl(url);
  }

  Future<void> _abort(WidgetRef ref, InProgressOp op) async {
    final write = ref.read(gitWriteOperationsProvider);
    if (op == InProgressOp.merge) await write.mergeAbort(repo);
    if (op == InProgressOp.cherryPick) await write.cherryPickAbort(repo);
    ref.invalidate(repoStateProvider(repo));
  }

  Future<void> _continue(WidgetRef ref, InProgressOp op) async {
    final write = ref.read(gitWriteOperationsProvider);
    if (op == InProgressOp.merge) await write.mergeContinue(repo);
    if (op == InProgressOp.cherryPick) await write.cherryPickContinue(repo);
    ref.invalidate(repoStateProvider(repo));
  }
}
```

- [ ] **Step 3: Wire in Shell** — when `repoStateProvider` reports merge/cherry-pick, the bottom panel becomes ConflictResolutionPanel (override Working Copy or Commit Details).

- [ ] **Step 4: Commit**

```bash
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(ui): conflict resolution panel for merge / cherry-pick"
```

---

## Sub-slice 2E — Clone + toolbar dropdowns + context menus + polish

### Task E1: clone implementation (TDD)

**Files:**
- Create: `test/infrastructure/git/git_cli_write_operations_clone_test.dart`
- Modify: `lib/infrastructure/git/git_cli_write_operations.dart`

- [ ] **Step 1: Test** (uses local file:// URL — already supported by git)

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/infrastructure/git/git_cli_write_operations.dart';
import 'package:path/path.dart' as p;
import '../../_helpers/repo_fixture.dart';

void main() {
  test('clone from local source repo', () async {
    final src = await RepoFixture.withLinearHistory(2);
    final dest = p.join(Directory.systemTemp.path, 'gitopen-clonetest-${DateTime.now().millisecondsSinceEpoch}');
    try {
      final sut = GitCliWriteOperations();
      await sut.clone(src.path, dest).toList();
      expect(Directory(p.join(dest, '.git')).existsSync(), isTrue);
    } finally {
      await src.dispose();
      try { Directory(dest).deleteSync(recursive: true); } catch (_) {}
    }
  });
}
```

- [ ] **Step 2: Implement**

```dart
@override
Stream<GitProgress> clone(String url, String destination, {AuthSpec? auth}) async* {
  final args = ['clone', '--progress', url, destination];
  await for (final p in _runProgressStream('.', args, auth: auth)) yield p;
}
```

Note: `_runProgressStream` uses `'.'` as cwd for clone since the destination doesn't exist yet.

- [ ] **Step 3: Commit**

```bash
git add lib test
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(infra): clone with progress stream (TDD)"
```

---

### Task E2: Clone dialog + welcome screen

**Files:**
- Create: `lib/ui/dialogs/clone_dialog.dart`
- Create: `lib/ui/welcome/welcome_screen.dart`
- Modify: `lib/ui/shell/repo_selector.dart` — add Clone item

- [ ] **Step 1: Clone dialog**

```dart
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/operations/operations_notifier.dart';
import '../../application/providers.dart';

class CloneDialog extends ConsumerStatefulWidget {
  const CloneDialog({super.key});
  static Future<void> show(BuildContext context) => showDialog(context: context, builder: (_) => const CloneDialog());
  @override
  ConsumerState<CloneDialog> createState() => _State();
}

class _State extends ConsumerState<CloneDialog> {
  final _urlCtl = TextEditingController();
  final _destCtl = TextEditingController();
  bool _openAfter = true;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Clone repository'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _urlCtl, autofocus: true, decoration: const InputDecoration(labelText: 'Repository URL')),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _destCtl, decoration: const InputDecoration(labelText: 'Destination'))),
            IconButton(icon: const Icon(Icons.folder_open), onPressed: _pickDest),
          ]),
          Row(children: [
            Checkbox(value: _openAfter, onChanged: (v) => setState(() => _openAfter = v ?? true)),
            const Text('Open after clone'),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(onPressed: _busy ? null : _clone, child: _busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Clone')),
      ],
    );
  }

  Future<void> _pickDest() async {
    final dir = await getDirectoryPath();
    if (dir != null) _destCtl.text = dir;
  }

  Future<void> _clone() async {
    if (_urlCtl.text.isEmpty || _destCtl.text.isEmpty) return;
    final url = _urlCtl.text.trim();
    final dest = _destCtl.text.trim();
    setState(() => _busy = true);
    final ops = ref.read(operationsProvider.notifier);
    final id = ops.start(OpKind.clone, 'Cloning $url');
    final write = ref.read(gitWriteOperationsProvider);
    try {
      await for (final ev in write.clone(url, dest)) {
        ops.updateProgress(id, ev.fraction, ev.phase);
      }
      ops.finishSuccess(id);
      if (_openAfter && mounted) {
        final manager = ref.read(workspaceManagerProvider.notifier);
        final ws = await manager.open(dest);
        ref.read(activeWorkspaceIdProvider.notifier).state = ws.location.id;
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ops.finishFailure(id, e.toString());
      if (mounted) setState(() => _busy = false);
    }
  }
}
```

- [ ] **Step 2: Welcome screen** (when no workspaces open)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/active_workspace_provider.dart';
import '../../application/providers.dart';
import '../dialogs/clone_dialog.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_special, size: 48, color: Color(0xFF4EC9B0)),
          const SizedBox(height: 16),
          const Text('Welcome to GitOpen', style: TextStyle(color: Color(0xFFD4D4D4), fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Open or clone a repository to begin.', style: TextStyle(color: Color(0xFF888892))),
          const SizedBox(height: 24),
          Row(mainAxisSize: MainAxisSize.min, children: [
            ElevatedButton.icon(
              onPressed: () => _openRepo(context, ref),
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text('Open repository'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => CloneDialog.show(context),
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Clone'),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _openRepo(BuildContext context, WidgetRef ref) async {
    final picker = ref.read(folderPickerProvider);
    final path = await picker.pickFolder('Open repository');
    if (path == null) return;
    final manager = ref.read(workspaceManagerProvider.notifier);
    final ws = await manager.open(path);
    ref.read(activeWorkspaceIdProvider.notifier).state = ws.location.id;
  }
}
```

- [ ] **Step 3: Add "Clone repository..." to RepoSelector menu** — just below "Open repository..."

- [ ] **Step 4: Route welcome screen in Shell when no workspaces open**

- [ ] **Step 5: Commit**

```bash
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(ui): clone dialog + welcome screen + menu entry"
```

---

### Task E3: Toolbar dropdowns (Branch + Stash)

**Files:**
- Modify: `lib/ui/toolbar/git_toolbar.dart` — extend with two MenuAnchor dropdowns

- [ ] **Step 1: Branch dropdown items**: New branch from HEAD, Switch branch, Delete branch, Rename current branch.
- [ ] **Step 2: Stash dropdown items**: Stash changes, Apply latest, Pop latest, View stashes.

Each opens the appropriate dialog (BranchCreateDialog for new branch, ConfirmDialog for delete, etc.) or invokes the write operation directly.

- [ ] **Step 3: Commit**

```bash
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(ui): Branch and Stash toolbar dropdowns"
```

---

### Task E4: Commit row context menu + tag context menu

**Files:**
- Modify: `lib/ui/commit_graph/commit_row.dart` — add `onSecondaryTapDown`
- Modify: `lib/ui/sidebar/sidebar.dart` — tag rows get context menu

- [ ] **Step 1: Commit row right-click**

`showMenu` with items: Cherry-pick into current, Create branch here…, Tag here…, Copy SHA, Copy short SHA, Reset to here ▾ (sub-menu with soft/mixed/hard, with confirm on hard).

- [ ] **Step 2: Tag context menu**: Checkout, Push tag, Delete tag (confirm).

- [ ] **Step 3: Stash context menu**: Apply, Pop, Drop (confirm).

- [ ] **Step 4: Commit**

```bash
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(ui): context menus on commit row, tag, stash"
```

---

### Task E5: Keyboard shortcuts + final polish

**Files:**
- Modify: `lib/main.dart` — wrap the Shell in `Shortcuts` / `Actions`
- Create: `lib/ui/shortcuts/shortcuts.dart`

- [ ] **Step 1: Define intents and actions**

```dart
class CommitIntent extends Intent { const CommitIntent(); }
class CommitAndPushIntent extends Intent { const CommitAndPushIntent(); }
class FetchIntent extends Intent { const FetchIntent(); }
class RefreshIntent extends Intent { const RefreshIntent(); }
class OpenRepoSelectorIntent extends Intent { const OpenRepoSelectorIntent(); }
```

Bindings:
- `Ctrl+Enter` → CommitIntent (only when focus is in commit message)
- `Ctrl+Shift+Enter` → CommitAndPushIntent
- `F5` → FetchIntent
- `Ctrl+R` → RefreshIntent
- `Ctrl+T` → OpenRepoSelectorIntent

- [ ] **Step 2: Wire to existing widgets**

The CommitCompose widget listens for CommitIntent and triggers commit. The toolbar handles FetchIntent. Etc.

- [ ] **Step 3: Final test pass + commit**

```bash
& 'C:\src\flutter\bin\flutter.bat' test
& 'C:\src\flutter\bin\flutter.bat' analyze
& 'C:\src\flutter\bin\flutter.bat' build windows --debug
git add lib
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "feat(ui): keyboard shortcuts (Ctrl+Enter commit, F5 fetch, Ctrl+R refresh)"
```

---

### Task E6: Slice 2 wrap-up

**Files:**
- Modify: `README.md` — document Slice 2 features
- Modify: `docs/qa-checklist.md` — extend with write-op smoke tests

- [ ] **Step 1: README section** describing daily writes, clone, conflict resolution.
- [ ] **Step 2: QA checklist additions**: clone a public repo, fetch / pull / push on a real GitHub repo, stash flow, merge with conflict and resolve via VS Code, cherry-pick a commit.
- [ ] **Step 3: Tag the slice**

```bash
git add README.md docs
git -c user.email=s.porta@novomatic.it -c user.name=s.porta commit -m "docs: Slice 2 README + QA checklist"
git tag -a slice-2-write-ops -m "Slice 2: daily write ops + merge + cherry-pick + clone"
```

---

## Self-Review

**Spec coverage:**
- §1 scope: covered across 2A-2E
- §3.2 Result types: Task A2
- §3.3 GitWriteOperations contract: Task A4
- §4 Working Copy panel: Tasks B6, B7, B8
- §5 Background ops + toast + activity panel: Tasks A5, A6, persistence in A1
- §5.6 activity_log table: Task A1
- §6 Auth: Tasks A7, A8 (Slice 2A) + C3 + C5 + C6 (wiring + GitHub OAuth)
- §7 Conflict resolution: Task D4 + D2 outcome variants
- §8 Clone: Tasks E1, E2
- §9 UI surface: toolbar (C4 + E3), context menus (B10 + E4)
- §10 Testing strategy: every TDD task covers its method; manual QA in E6

**Placeholder scan:** No "TBD" or "implement later". Two tasks (B8 hunk staging UI internals, C5 auth auto-prompt details) intentionally summarize ~80-200 LoC with a pattern sketch rather than full code — they reference well-established patterns from earlier tasks (diff parser already exists, AuthDialog.show already wired). If the implementer wants more detail, the spec §4.2 and §6.4 provide it.

**Type consistency:**
- `GitResult<T>`, `GitSuccess<T>`, `GitFailure<T>` used consistently in A2 → all later tasks
- `OpKind`, `OperationStatus` defined in A5 → used in C4, C5, E2
- `MergeOutcome`, `CherryPickOutcome` sealed in A4 → consumed in D2, D3, D4
- `RepoLocation`, `CommitSha`, `WorkingFileEntry` reuse existing Slice 1 types
- `AuthSpec` defined in A4 → used in A7, A8, C3, C6

**Scope check:** Slice 2 spec is ~5 weeks of work. The 5 sub-slices map 1:1 to logical milestones (foundation → daily writes → sync → stash/merge/cherry-pick → clone+polish), each producing a buildable artefact. The plan is large but cohesive.

---

## Execution

Plan saved to `docs/superpowers/plans/2026-05-12-slice2-write-ops.md`. Per user's explicit directive ("procedi e non chiedermi piu niente"), proceed directly to Subagent-Driven Execution without offering the choice. The terminal step of writing-plans is to invoke `superpowers:subagent-driven-development`.
