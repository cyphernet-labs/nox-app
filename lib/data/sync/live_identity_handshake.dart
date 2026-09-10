import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/server_frame.dart';
import 'package:nox_app/data/sync/live_session_starter.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/domain/model/session/pair_refusal.dart';
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
/// The server refused for a reason that is not about the link: an internal
/// error, a rate limit, a code this build does not know. Retryable, and
/// deliberately NOT one of the four refusals - telling somebody their invite is
/// spent over a server hiccup sends them looking for a new one they do not need.
class PairingFailed implements Exception {
  const PairingFailed();

  @override
  String toString() => 'PairingFailed';
}

class PairingRefused implements Exception {
  const PairingRefused({required this.reason});

  /// Which of the four refusals this was. They stay apart because each leads
  /// the person somewhere different, and one shared "it did not work" would
  /// make the app invent wording it does not know.
  final PairRefusal reason;

  @override
  String toString() => 'PairingRefused(${reason.name})';
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
      // No channel, or no answer within the command timeout. Nothing was
      // decided, so this is "try again" rather than an outcome.
      throw const IdentityHandshakeTimeout();
    }
    if (!reply.ok) {
      final refusal = _refusalFor(reply.errorCode);
      // A code that is not one of the two pairing refusals is not a refusal at
      // all - `internal`, `rate_limited`, a code this build predates. The
      // contract's evolution rule says treat it as `internal` and let the
      // person retry; calling it "this link cannot be used" would send them
      // hunting for a new invite over a server hiccup.
      if (refusal == null) throw const PairingFailed();
      throw PairingRefused(reason: refusal);
    }
    final data = reply.data;
    if (data is! Map<String, dynamic>) throw const IdentityHandshakeTimeout();
    final id = data['identity'];
    if (id is! Map<String, dynamic>) throw const IdentityHandshakeTimeout();
    return _identityOf(id);
  }

  static PairRefusal? _refusalFor(String? code) => switch (code) {
    'invalid_token' => PairRefusal.notUsable,
    'token_expired' => PairRefusal.expired,
    _ => null,
  };

  IdentityHandshake _identityOf(Map<String, dynamic> id) {
    final created = id['created'];
    return IdentityHandshake(
      // Type-checked like the socket's parser, and here the stakes are higher:
      // a throw at this point happens AFTER the server committed the pairing
      // and burned a one-shot claim token, so the same link cannot be presented
      // again and the person waits for an operator to read a fresh one out of
      // the server log.
      authorId: id['id'] is String ? id['id'] as String : '',
      label: id['label'] is String ? id['label'] as String : '',
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
