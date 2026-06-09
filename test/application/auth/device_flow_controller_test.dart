import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitopen/application/auth/device_flow_controller.dart';

class _FakeSession implements DeviceFlowSession {
  _FakeSession(this.userCode, this.verificationUri, this.token);
  @override
  final String userCode;
  @override
  final String verificationUri;
  final Completer<String> token;

  @override
  Future<String> pollForToken() => token.future;
}

class _FakePort implements DeviceFlowPort {
  _FakePort(this.session);
  final Completer<DeviceFlowSession> session;

  @override
  Future<DeviceFlowSession> requestDeviceCode() => session.future;
}

void main() {
  test('happy path: requesting → awaiting(code, uri) → succeeded(token)',
      () async {
    final session =
        _FakeSession('ABCD-1234', 'https://github.com/login/device',
            Completer<String>());
    final port = _FakePort(Completer<DeviceFlowSession>());
    final c = DeviceFlowController(port);
    final seen = <DeviceFlowState>[];
    c.states.listen(seen.add);

    final run = c.start();
    port.session.complete(session);
    session.token.complete('tok_123');
    await run;
    // Stream delivery is async; let pending events flush before asserting.
    await Future<void>.delayed(Duration.zero);

    expect(seen, hasLength(3));
    expect(seen[0], isA<DeviceFlowRequestingCode>());
    final awaiting = seen[1] as DeviceFlowAwaitingAuthorization;
    expect(awaiting.userCode, 'ABCD-1234');
    expect(awaiting.verificationUri, 'https://github.com/login/device');
    expect((seen[2] as DeviceFlowSucceeded).token, 'tok_123');
    c.cancel();
  });

  test('device-code request failure → failed with the error text', () async {
    final port = _FakePort(Completer<DeviceFlowSession>());
    final c = DeviceFlowController(port);

    final run = c.start();
    port.session.completeError(StateError('Client ID not configured'));
    await run;

    final s = c.state;
    expect(s, isA<DeviceFlowFailed>());
    expect((s as DeviceFlowFailed).message, contains('Client ID'));
    c.cancel();
  });

  test('poll failure (e.g. expiry) → failed', () async {
    final session = _FakeSession('X', 'uri', Completer<String>());
    final port = _FakePort(Completer<DeviceFlowSession>());
    final c = DeviceFlowController(port);

    final run = c.start();
    port.session.complete(session);
    session.token
        .completeError(TimeoutException('the device code expired'));
    await run;

    expect(c.state, isA<DeviceFlowFailed>());
    expect((c.state as DeviceFlowFailed).message, contains('expired'));
    c.cancel();
  });

  test('cancel mid-poll drops a late token: no succeeded state', () async {
    final session = _FakeSession('X', 'uri', Completer<String>());
    final port = _FakePort(Completer<DeviceFlowSession>());
    final c = DeviceFlowController(port);
    final seen = <DeviceFlowState>[];
    c.states.listen(seen.add);

    final run = c.start();
    port.session.complete(session);
    // Let the awaiting state land, then close the "dialog".
    await Future<void>.delayed(Duration.zero);
    c.cancel();
    session.token.complete('tok_late');
    await run;
    await Future<void>.delayed(Duration.zero);

    expect(seen.whereType<DeviceFlowSucceeded>(), isEmpty);
    expect(c.state, isA<DeviceFlowAwaitingAuthorization>());
  });

  test('reset returns to idle only from failed', () async {
    final port = _FakePort(Completer<DeviceFlowSession>());
    final c = DeviceFlowController(port)..reset();
    expect(c.state, isA<DeviceFlowIdle>());

    final run = c.start();
    port.session.completeError(StateError('boom'));
    await run;
    expect(c.state, isA<DeviceFlowFailed>());

    c.reset();
    expect(c.state, isA<DeviceFlowIdle>());
    c.cancel();
  });

  test('start is a no-op while a flow is in flight', () async {
    final session = _FakeSession('X', 'uri', Completer<String>());
    final port = _FakePort(Completer<DeviceFlowSession>());
    final c = DeviceFlowController(port);
    final seen = <DeviceFlowState>[];
    c.states.listen(seen.add);

    final first = c.start();
    final second = c.start(); // ignored: already requesting
    port.session.complete(session);
    session.token.complete('tok');
    await first;
    await second;
    await Future<void>.delayed(Duration.zero);

    expect(seen.whereType<DeviceFlowRequestingCode>(), hasLength(1));
    expect(seen.whereType<DeviceFlowSucceeded>(), hasLength(1));
    c.cancel();
  });
}
