import 'dart:async';

/// User-facing handle for one started device-flow authorisation: the code to
/// type on the provider's page plus a way to await the resulting token.
abstract interface class DeviceFlowSession {
  String get userCode;
  String get verificationUri;

  /// Resolves to the access token once the user authorises, or throws when
  /// the code expires / the provider rejects the flow.
  Future<String> pollForToken();
}

/// Application port over the OAuth device-flow transport (implemented in
/// infrastructure with real HTTP).
// ignore: one_member_abstracts
abstract interface class DeviceFlowPort {
  Future<DeviceFlowSession> requestDeviceCode();
}

/// States of the device-flow sign-in, in the order they normally occur.
sealed class DeviceFlowState {
  const DeviceFlowState();
}

/// Nothing started yet (or reset after a failure).
final class DeviceFlowIdle extends DeviceFlowState {
  const DeviceFlowIdle();
}

/// The device code is being requested from the provider.
final class DeviceFlowRequestingCode extends DeviceFlowState {
  const DeviceFlowRequestingCode();
}

/// The user must now enter [userCode] at [verificationUri]; the token is
/// being polled in the background.
final class DeviceFlowAwaitingAuthorization extends DeviceFlowState {
  const DeviceFlowAwaitingAuthorization(this.userCode, this.verificationUri);
  final String userCode;
  final String verificationUri;
}

/// Authorisation completed; [token] is the access token.
final class DeviceFlowSucceeded extends DeviceFlowState {
  const DeviceFlowSucceeded(this.token);
  final String token;
}

/// The flow failed (request error, poll error, or expiry).
final class DeviceFlowFailed extends DeviceFlowState {
  const DeviceFlowFailed(this.message);
  final String message;
}

/// Drives the OAuth device-flow state machine:
/// idle → requestingCode → awaitingAuthorization → succeeded | failed.
///
/// Pure application logic — the transport is behind [DeviceFlowPort] — so the
/// transitions are unit-testable with fakes. [cancel] makes any in-flight
/// result a no-op (used when the dialog closes mid-poll, so a token that
/// arrives later can't fire callbacks on a dead widget).
final class DeviceFlowController {
  DeviceFlowController(this._port);
  final DeviceFlowPort _port;

  final StreamController<DeviceFlowState> _states =
      StreamController<DeviceFlowState>.broadcast();
  DeviceFlowState _state = const DeviceFlowIdle();
  bool _cancelled = false;

  /// The current state; new listeners should read this before listening.
  DeviceFlowState get state => _state;

  /// State transitions, in order. Closed by [cancel].
  Stream<DeviceFlowState> get states => _states.stream;

  /// Starts (or, from [DeviceFlowFailed]/idle, restarts) the flow. No-op when
  /// a flow is already in flight or finished.
  Future<void> start() async {
    if (_cancelled) return;
    if (_state is! DeviceFlowIdle && _state is! DeviceFlowFailed) return;
    _emit(const DeviceFlowRequestingCode());
    final DeviceFlowSession session;
    try {
      session = await _port.requestDeviceCode();
    } on Object catch (e) {
      _emit(DeviceFlowFailed('$e'));
      return;
    }
    if (_cancelled) return;
    _emit(DeviceFlowAwaitingAuthorization(
      session.userCode,
      session.verificationUri,
    ));
    try {
      final token = await session.pollForToken();
      _emit(DeviceFlowSucceeded(token));
    } on Object catch (e) {
      _emit(DeviceFlowFailed('$e'));
    }
  }

  /// Returns to [DeviceFlowIdle] after a failure so the user can retry.
  void reset() {
    if (_cancelled) return;
    if (_state is DeviceFlowFailed) _emit(const DeviceFlowIdle());
  }

  /// Stops the machine: every in-flight result is dropped and the [states]
  /// stream closes. Idempotent.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    unawaited(_states.close());
  }

  void _emit(DeviceFlowState s) {
    if (_cancelled) return;
    _state = s;
    _states.add(s);
  }
}
