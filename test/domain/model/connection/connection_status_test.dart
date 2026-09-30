import 'package:flutter_test/flutter_test.dart';
import 'package:nox_app/domain/model/connection/connection_path.dart';
import 'package:nox_app/domain/model/connection/connection_status.dart';

void main() {
  test('the corner shows Connecting while a path comes up or catches up', () {
    expect(const ConnectionStatus(state: LinkState.connecting).showsConnecting, isTrue);
    expect(const ConnectionStatus(state: LinkState.catchingUp).showsConnecting, isTrue);
    expect(const ConnectionStatus(state: LinkState.online).showsConnecting, isFalse);
    expect(const ConnectionStatus(state: LinkState.offline).showsConnecting, isFalse);
  });

  test('the Tor badge shows only on the Tor path and never while offline (FR-028)', () {
    for (final state in [LinkState.connecting, LinkState.catchingUp, LinkState.online]) {
      expect(
        ConnectionStatus(state: state, path: ConnectionPath.tor).showsTorBadge,
        isTrue,
        reason: state.name,
      );
      expect(
        ConnectionStatus(state: state, path: ConnectionPath.direct).showsTorBadge,
        isFalse,
        reason: state.name,
      );
    }
    expect(const ConnectionStatus(state: LinkState.offline, path: ConnectionPath.tor).showsTorBadge, isFalse);
    expect(const ConnectionStatus(state: LinkState.serverMismatch, path: ConnectionPath.tor).showsTorBadge, isFalse);
  });

  test('only offline is offline, and only online is current', () {
    expect(const ConnectionStatus(state: LinkState.offline).isOffline, isTrue);
    expect(const ConnectionStatus(state: LinkState.connecting).isOffline, isFalse);
    expect(const ConnectionStatus(state: LinkState.online).isCurrent, isTrue);
    expect(const ConnectionStatus(state: LinkState.catchingUp).isCurrent, isFalse);
  });
}
