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
  const IdentityHandshake({required this.authorId, required this.label, required this.created, required this.isOwner});

  final String authorId;
  final String label;

  /// Whether this person owns the server (contract §3, §8A). Null means the
  /// server did not state it, which is not the same as "does not own".
  ///
  /// `required` although nullable, on the project's own precedent: a null here
  /// is not a neutral default. `adoptServerIdentity` reads it as "say nothing,
  /// leave the stored answer alone", so a construction site that forgets the
  /// field would silently freeze a badge that ownership had moved away from.
  /// The compiler makes every caller decide instead.
  final bool? isOwner;

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

  /// How long the person at the door waits for the owner to answer.
  ///
  /// Slightly LONGER than the server's own five-minute window on purpose: when
  /// both clocks are close to running out, the server's answer should be the
  /// one that arrives. Giving up first would show "the owner did not answer"
  /// while the real outcome was still on its way.
  static const Duration approvalWait = Duration(minutes: 5, seconds: 30);

  /// How often the same link is presented again while waiting.
  ///
  /// The wait is not a single held request: a dropped socket takes the
  /// connection the outcome was addressed to with it, and the server marks a
  /// NEW connection only when the link is presented on it. Re-presenting is the
  /// server's own recovery path (contract §8B) — it returns the same pending
  /// request, or the recorded outcome if the owner has answered meanwhile — so
  /// the client uses it rather than trying to detect the drop.
  static const Duration approvalPoll = Duration(seconds: 20);

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
    final deadline = DateTime.now().add(approvalWait);
    var presented = false;
    while (true) {
      final CommandReply reply;
      try {
        reply = await _socket.pair(token: link.token, deviceKey: deviceKey, platform: platform);
      } on Object {
        // No channel, or no answer within the command timeout.
        //
        // Before anything was presented this is simply "try again" — nothing
        // was decided. Once a request IS waiting it is a dropped socket, and
        // giving up would throw away a decision that may already have been
        // taken: the link is presented again once the channel is back.
        if (!presented || DateTime.now().isAfter(deadline)) throw const IdentityHandshakeTimeout();
        await Future<void>.delayed(approvalPoll);
        await _starter.restart();
        continue;
      }
      if (!reply.ok) {
        throw PairingRefused(reason: _refusalFor(reply.errorCode));
      }
      final data = reply.data;
      if (data is! Map<String, dynamic>) throw const IdentityHandshakeTimeout();

      // A person invite does not finish here: the answer belongs to the owner
      // and has not been given (contract §8B). Anything else finished the
      // moment it was answered, and older servers say nothing at all — which
      // is not "pending", so the identity below is read as it always was.
      if (data['status'] == 'pending') {
        presented = true;
        final requestId = data['request_id'] is String ? data['request_id'] as String : '';
        final resolved = await _awaitPairOutcome(requestId, approvalPoll);
        if (resolved == null) {
          // No answer yet. Present again, which re-marks whichever connection
          // is current and hands back the recorded outcome if there is one.
          if (DateTime.now().isAfter(deadline)) throw const PairingRefused(reason: PairRefusal.noAnswer);
          continue;
        }
        return _outcomeOf(resolved);
      }

      final id = data['identity'];
      if (id is! Map<String, dynamic>) throw const IdentityHandshakeTimeout();
      return _identityOf(id);
    }
  }

  /// Waits for the server's answer about one request, or gives up after
  /// [window] so the caller can present the link again.
  ///
  /// Listening on the socket's event stream rather than on the connection: the
  /// stream outlives a reconnect, so an answer that arrives on a later
  /// connection is still seen.
  Future<Map<String, dynamic>?> _awaitPairOutcome(String requestId, Duration window) async {
    final answered = Completer<Map<String, dynamic>?>();
    final sub = _socket.events.listen((event) {
      if (event.event != ServerEvent.personPairResolved) return;
      // About THIS request. Two people knocking is two decisions, and the owner
      // may have answered the other one first.
      if (requestId.isNotEmpty && event.data['request_id'] != requestId) return;
      if (!answered.isCompleted) answered.complete(event.data);
    });
    final timer = Timer(window, () {
      if (!answered.isCompleted) answered.complete(null);
    });
    try {
      return await answered.future;
    } finally {
      timer.cancel();
      await sub.cancel();
    }
  }

  /// Turns the resolved event into an outcome: an identity, or the refusal that
  /// says what to do next.
  IdentityHandshake _outcomeOf(Map<String, dynamic> resolved) {
    final outcome = resolved['outcome'];
    if (outcome == 'declined') throw const PairingRefused(reason: PairRefusal.declined);
    if (outcome != 'approved') throw const PairingRefused(reason: PairRefusal.noAnswer);
    final id = resolved['identity'];
    if (id is! Map<String, dynamic>) throw const IdentityHandshakeTimeout();
    return _identityOf(id);
  }

  static PairRefusal _refusalFor(String? code) => switch (code) {
    'token_expired' => PairRefusal.expired,
    'pair_declined' => PairRefusal.declined,
    'pair_timeout' => PairRefusal.noAnswer,
    _ => PairRefusal.notUsable,
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
      isOwner: id['owner'] is bool ? id['owner'] as bool : null,
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
        pending.complete(
          IdentityHandshake(authorId: identity.id, label: identity.label, created: identity.created, isOwner: identity.isOwner),
        );
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
