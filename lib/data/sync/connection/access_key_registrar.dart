import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/connection/access_key_repository.dart';

/// Puts this device's onion access key on the server (phase 040, FR-016).
///
/// A device paired before phase 039, or paired with a server that was updated
/// later, has no key there; without one the onion service never opens to it.
/// So on every greeting from a server that declares support - `addresses` in
/// the reply (contract §2.1) - a device whose key is not known to be registered
/// sends `device.setAccessKey`. The same key twice is a success with no effect,
/// so a pairing that already registered it costs one harmless command.
@LazySingleton(env: [Environment.dev])
class AccessKeyRegistrar {
  AccessKeyRegistrar(this._socket, this._keys);

  final NoxSocketClient _socket;
  final AccessKeyRepository _keys;

  /// The server may refuse a key as unusable or as somebody else's; each
  /// refusal is answered with a new key, but no more than this many times in
  /// one session (FR-017). A server that refuses every key is not helped by a
  /// loop.
  static const int maxNewKeys = 3;

  StreamSubscription<SessionPhase>? _phaseSub;
  int _newKeys = 0;
  bool _running = false;

  void start() {
    _phaseSub ??= _socket.phase.listen((phase) {
      if (phase == SessionPhase.catchingUp) unawaited(_register());
    });
  }

  Future<void> stop() async {
    await _phaseSub?.cancel();
    _phaseSub = null;
    _newKeys = 0;
  }

  Future<void> _register() async {
    if (_running || !_socket.supportsAccessKeys) return;
    _running = true;
    try {
      if ((await _keys.isRegistered()).data ?? false) return;
      while (true) {
        final key = (await _keys.deviceKey()).data;
        if (key == null) return;
        final reply = await _socket.send('device.setAccessKey', <String, dynamic>{'access_key': key.publicBase64});
        if (reply.ok) {
          await _keys.markRegistered(true);
          logRepository.debug(target: this, message: 'access key: registered');
          return;
        }
        // Unusable or taken: a new key, and once more (FR-017).
        if (reply.errorCode == 'invalid_request' && _newKeys < maxNewKeys) {
          _newKeys++;
          logRepository.debug(target: this, message: 'access key: refused, trying a new one ($_newKeys of $maxNewKeys)');
          if (!(await _keys.regenerate()).hasData) return;
          continue;
        }
        // `unauthenticated`: this device was revoked mid-session. The server
        // closes the socket and the next greeting is refused, which is the
        // revocation path - nothing to add here. Anything else: the next
        // greeting tries again.
        logRepository.debug(target: this, message: 'access key: not registered (${reply.errorCode})');
        return;
      }
    } on SocketUnavailableException {
      // The connection went; the next greeting tries again.
    } finally {
      _running = false;
    }
  }
}
