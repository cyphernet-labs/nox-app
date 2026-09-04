import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/server_frame.dart';
import 'package:nox_app/data/sync/live_session_starter.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';

/// What the server said about who just connected. A domain value on purpose:
/// the onboarding decision is taken from THIS, never from "was there a hello
/// frame". Contract §8.1 moves the same distinction onto the pairing reply at
/// stage 2, and nothing outside the transport layer may notice that it moved.
class IdentityHandshake {
  const IdentityHandshake({required this.authorId, required this.label, required this.created});

  final String authorId;
  final String label;

  /// Whether the server brought this person into being just now. Null means it
  /// did not say — an older server, or a frame that does not carry the
  /// distinction. Neither outcome may be assumed from null: one steals the
  /// naming step from a newcomer, the other overwrites a returning person's
  /// name, and the second is the defect this whole path exists to remove.
  final bool? created;

  bool get outcomeStated => created != null;
}

/// Raised when the server did not answer in time, or answered without saying
/// who connected. The caller shows a readable error with a retry; it must not
/// guess an outcome.
class IdentityHandshakeTimeout implements Exception {
  const IdentityHandshakeTimeout();

  @override
  String toString() => 'IdentityHandshakeTimeout';
}

/// The server refused the pairing token. Distinct from a timeout because the
/// person's next action differs: get a new link rather than try again.
class PairingRefused implements Exception {
  const PairingRefused({required this.expired});

  /// True when the token was still real but had outlived its ten minutes.
  /// Worth telling apart: "issue a new invite" versus "this one is not usable".
  final bool expired;

  @override
  String toString() => 'PairingRefused(expired: $expired)';
}

/// Owns the sign-in handshake: brings the live channel up, waits for the
/// greeting, and hands back what the server said.
///
/// It exists because sign-in stopped being a local decision. The app used to
/// decide whether someone needed onboarding from a hardcoded set before ever
/// connecting; now the server decides, so somebody has to own the wait.
@LazySingleton(env: [Environment.dev])
class LiveIdentityHandshake {
  LiveIdentityHandshake(this._socket, this._starter);

  final NoxSocketClient _socket;
  final LiveSessionStarter _starter;

  /// How long a person waits before being told to try again. Meaningful only
  /// because `stop()` resets the reconnect ladder: without that reset a device
  /// that had been offline for a while would spend this whole window inside a
  /// single backoff sleep, never attempting a connection.
  static const Duration timeout = Duration(seconds: 20);

  Completer<IdentityHandshake>? _pending;
  StreamSubscription<SessionPhase>? _phases;
  Timer? _timer;

  /// True while a handshake is being awaited.
  ///
  /// There is deliberately no anonymous window for this to guard: the caller
  /// stores the login identifier BEFORE greeting, so the greeting that follows
  /// always states a person. Gating the credentials provider on this instead
  /// would deadlock, since the handshake is what brings the channel up.
  bool get inFlight => _pending != null;

  /// Presents a pairing token and returns what the server said about who was
  /// just paired.
  ///
  /// The caller MUST re-greet afterwards ([greet]) once the session is stored.
  /// The connection this ran on was greeted before anyone was paired, so the
  /// server still knows it as whoever greeted then — messages sent on it would
  /// be stamped with that identity, not the person who just paired.
  ///
  /// The socket has to be brought up against the address from the LINK, which
  /// the caller has already stored — [LiveSessionStarter.restart] reads it from
  /// there. `pair` is then the one command allowed before a greeting.
  Future<IdentityHandshake> pair({required PairingLink link, required String deviceKey, required String platform}) async {
    await _starter.restart();
    final CommandReply reply;
    try {
      reply = await _socket.pair(token: link.token, deviceKey: deviceKey, platform: platform);
    } on Object {
      // No channel, or no answer within the command timeout. The person is
      // told to try again; nothing was decided.
      throw const IdentityHandshakeTimeout();
    }
    if (!reply.ok) {
      throw PairingRefused(expired: reply.errorCode == 'token_expired');
    }
    final data = reply.data;
    final id = data is Map<String, dynamic> ? data['identity'] : null;
    if (id is! Map<String, dynamic>) throw const IdentityHandshakeTimeout();
    final created = id['created'];
    return IdentityHandshake(
      authorId: id['id'] as String? ?? '',
      label: id['label'] as String? ?? '',
      // Absent stays absent: "outcome not stated" is neither outcome, and the
      // sign-in path must not be handed a guess.
      created: created is bool ? created : null,
    );
  }

  /// Restarts the channel and waits for the server to say who connected.
  ///
  /// The timeout lives HERE, inside the owner of the state, and not as a
  /// `.timeout()` around the call. `Future.timeout` does not cancel its source:
  /// the caller would be released, this body would keep running, the `finally`
  /// below would never execute, and `inFlight` would stay true for the life of
  /// the process — wedging every later sign-in attempt.
  Future<IdentityHandshake> greet() async {
    // Captured BEFORE anything is torn down. The phase stream replays its
    // current value to a new listener, so on an already-connected socket the
    // first event carries the PREVIOUS connection's identity — including the
    // anonymous greeting the app makes at boot, whose `created` is always
    // true. Answering from that would route every returning person into
    // onboarding without the server having been asked about them at all.
    final generation = _socket.greetingGeneration;
    final pending = Completer<IdentityHandshake>();
    _pending = pending;
    _timer = Timer(timeout, () {
      if (!pending.isCompleted) pending.completeError(const IdentityHandshakeTimeout());
    });
    _phases = _socket.phase.listen((phase) {
      if (phase == SessionPhase.unsupported) {
        // The peer refused in a way it will refuse again - a schema it does not
        // speak, or a malformed greeting. Waiting out the full timeout would
        // spend twenty seconds to reach the same answer, so say it now.
        if (!pending.isCompleted) pending.completeError(const IdentityHandshakeTimeout());
        return;
      }
      if (phase != SessionPhase.catchingUp && phase != SessionPhase.live) return;
      // Only an answer to OUR greeting counts.
      if (_socket.greetingGeneration <= generation) return;
      final identity = _socket.identity;
      if (identity == null || identity.id.isEmpty) return;
      if (!pending.isCompleted) {
        pending.complete(IdentityHandshake(authorId: identity.id, label: identity.label, created: identity.created));
      }
    });

    try {
      // restart() resets the reconnect ladder through stop(), so the first
      // attempt is immediate regardless of how long the device sat offline.
      await _starter.restart();
      return await pending.future;
    } finally {
      _timer?.cancel();
      _timer = null;
      await _phases?.cancel();
      _phases = null;
      _pending = null;
    }
  }
}

/// Reached the way the rest of the sync layer is reached, so callers outside
/// the dev environment degrade instead of throwing.
LiveIdentityHandshake? get liveIdentityHandshake => getIt.isRegistered<LiveIdentityHandshake>() ? getIt<LiveIdentityHandshake>() : null;
