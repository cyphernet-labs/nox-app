import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/remote/socket/server_frame.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/data/sync/live_session_starter.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/di/global_aliases.dart';
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

/// The server refused for a reason that is not about the link: an internal
/// error, a rate limit, a code this build does not know. Retryable, and
/// deliberately NOT one of the pairing refusals - telling somebody their invite
/// is spent over a server hiccup sends them looking for a new one they do not
/// need.
class PairingFailed implements Exception {
  const PairingFailed();

  @override
  String toString() => 'PairingFailed';
}

/// The server refused the pairing token itself, or the request an invite opened
/// ended without a pairing. Distinct from [PairingFailed] because the person's
/// next action differs: get a new link rather than retry.
class PairingRefused implements Exception {
  const PairingRefused({required this.reason});

  /// Which refusal this was. They stay apart because each leads the person
  /// somewhere different, and one shared "it did not work" would make the app
  /// invent wording it does not know.
  final PairRefusal reason;

  @override
  String toString() => 'PairingRefused(${reason.name})';
}

/// The request an invite opened was withdrawn by this device - the person
/// pressed Cancel while it waited for approval (phase 046). Not a refusal:
/// nobody refused anything, and there is nothing to tell the person about it.
class PairingCancelled implements Exception {
  const PairingCancelled();

  @override
  String toString() => 'PairingCancelled';
}

/// An invite's request that waits for the device that issued the invite to
/// answer (contract §8A, phase 046), as the server first reported it.
class PairingPending {
  const PairingPending({required this.requestId, required this.waitUntil, this.expiresAt});

  /// The server's name for the request. Opaque, and not a secret.
  final String requestId;

  /// The request's deadline by the server's clock, as it stated it; null when
  /// it did not.
  final DateTime? expiresAt;

  /// When this device stops waiting, by its own clock - see
  /// [LiveIdentityHandshake.approvalWindow].
  final DateTime waitUntil;
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
  /// The socket has to be brought up towards the server the LINK named, which
  /// the caller has already stored - its key, its addresses and what the
  /// person set on the connection screen - [LiveSessionStarter.restart] reads
  /// them from there. The path is chosen as for any connection (phase 045):
  /// directly first, and through Tor when no direct address answers, `Use Tor`
  /// is on and an onion address is known - a machine link as much as an
  /// invite. `pair` goes out only on a channel that has verified the server's
  /// key, whichever path it took: a machine with another key never sees the
  /// token (SC-003 of 044).
  ///
  /// No device key in the command (phase 044): the server takes it from the
  /// connection, where this device has just proved it.
  ///
  /// An invite pairs nothing by itself (phase 046): the server answers that
  /// the request waits for the device that issued the invite, and this waits
  /// with it - [onPending] is told once it does - until that device answers,
  /// the person withdraws the request ([cancelPairing]), or the time runs out:
  /// the server's word on it, or [waitUntil] by this device's clock, whichever
  /// comes first. [waitUntil] is for a wait resumed after a restart (FR-011);
  /// a new one waits [approvalWindow].
  Future<IdentityHandshake> pair({
    required PairingLink link,
    required String platform,
    DateTime? waitUntil,
    void Function(PairingPending pending)? onPending,
  }) async {
    // Outcomes are listened for BEFORE the token goes out: the device that
    // issued the invite can answer within a frame of the request opening, and
    // an outcome delivered before anybody listened would leave this device
    // waiting out its whole deadline for an answer it already had. Held in
    // order until the wait begins.
    final nudges = StreamController<_Nudge>();
    final outcomes = _socket.events.listen((event) {
      if (event.event == ServerEvent.pairResolved && !nudges.isClosed) nudges.add(_Resolved(event.data));
    });
    try {
      await _starter.restart();
      final first = await _present(link.token, platform);
      if (first == null) {
        // No channel, or no answer within the command timeout. Nothing was
        // decided, so this is "try again" rather than an outcome.
        throw const IdentityHandshakeTimeout();
      }
      switch (first) {
        case _Paired(:final identity):
          return identity;
        case _Closed(:final error):
          throw error;
        case _Waiting(:final requestId, :final expiresAt):
          final until = waitUntil ?? DateTime.now().add(approvalWindow);
          onPending?.call(PairingPending(requestId: requestId, expiresAt: expiresAt, waitUntil: until));
          return await _awaitApproval(token: link.token, platform: platform, until: until, nudges: nudges);
      }
    } finally {
      await outcomes.cancel();
      // Not awaited: the done of a stream nobody listened to - every pairing
      // that never waited - never comes.
      unawaited(nudges.close());
    }
  }

  /// How long a pairing through an invite waits for approval by this
  /// device's clock: the invite's ten minutes - the request opened after the
  /// invite was issued, so it can never outlive them - and half a minute more
  /// for the server to say so itself. Measured from the first reply that said
  /// "pending", never from the server's `expires_at`: the two clocks need not
  /// agree, and a device whose clock runs ahead would otherwise give up on a
  /// request that still waits.
  static const Duration approvalWindow = Duration(minutes: 10, seconds: 30);

  /// How long each step of a withdrawal may take - the cancel, then the read
  /// of what the request ended as. A person who pressed Cancel is waiting to
  /// leave, and a request that stays open on a server out of reach ends at its
  /// own deadline anyway.
  static const Duration _withdrawStep = Duration(seconds: 5);

  /// The request being waited on, or null.
  _Approval? _approval;

  /// Withdraws the request a pairing waits on (contract §8A `pair.cancel`,
  /// FR-010): the token is spent and the device that issued the invite stops
  /// being asked. The pending [pair] then ends with [PairingCancelled] - or
  /// with the identity, when that device's Allow got there first: refusing a
  /// pairing that already happened would leave a key paired that nothing on
  /// this device knows.
  ///
  /// Best effort on a channel that is down: the person still leaves, and the
  /// request ends at its own deadline. Nothing to do when nothing waits.
  Future<void> cancelPairing() async {
    final approval = _approval;
    if (approval == null || approval.settled || approval.cancelling) return;
    approval.cancelling = true;
    logRepository.debug(target: this, message: 'pairing: withdrawing the request');
    final last = await _withdraw(approval);
    approval.settle(last is _Paired ? last : const _Closed(PairingCancelled()));
  }

  /// Waits for the answer to an invite's request.
  ///
  /// Everything that may have changed the answer is a nudge to present the
  /// token again - the repeat answers with the request's recorded outcome
  /// (contract §8A), which is the one source of truth here:
  ///
  /// * `pair.resolved` - but only as a hint. It names no request, so one left
  ///   over from an earlier request of this same device could otherwise be
  ///   read as this one's; only when there is no channel to ask over is the
  ///   event taken at its word;
  /// * a new connection - the event does not survive a disconnect, the
  ///   repeat does;
  /// * this device's own deadline - see [approvalWindow].
  ///
  /// A channel refused for good ends the wait: no answer can come over it.
  Future<IdentityHandshake> _awaitApproval({
    required String token,
    required String platform,
    required DateTime until,
    required StreamController<_Nudge> nudges,
  }) async {
    final approval = _Approval(token: token, platform: platform);
    _approval = approval;
    logRepository.debug(target: this, message: 'pairing: waiting for approval on the device that issued the invite');
    void nudge(_Nudge value) {
      if (!nudges.isClosed) nudges.add(value);
    }

    final connections = _socket.connectionOpened.listen((_) => nudge(const _Connection()));
    final phases = _socket.phase.listen((phase) {
      if (phase.isTerminal) nudge(const _Terminal());
    });
    final left = until.difference(DateTime.now());
    final deadline = Timer(left.isNegative ? Duration.zero : left, () => nudge(const _Deadline()));
    unawaited(_listen(approval, nudges.stream));
    try {
      return await approval.result.future;
    } finally {
      deadline.cancel();
      await connections.cancel();
      await phases.cancel();
      if (identical(_approval, approval)) _approval = null;
    }
  }

  /// Takes the nudges one at a time - each may present the token again, and
  /// two presentations at once would only race each other to the same answer.
  Future<void> _listen(_Approval approval, Stream<_Nudge> nudges) async {
    await for (final nudge in nudges) {
      if (approval.settled) break;
      final answer = await _consider(approval, nudge);
      if (answer != null) approval.settle(answer);
      if (approval.settled) break;
    }
  }

  /// What one nudge says about the request: an answer that ends the wait, or
  /// null to go on waiting.
  Future<_Answer?> _consider(_Approval approval, _Nudge nudge) async {
    // A withdrawal under way owns the outcome: it reads it itself, Allow
    // included, and acting here as well would only answer twice.
    if (approval.cancelling) return null;
    switch (nudge) {
      case _Terminal():
        return const _Closed(IdentityHandshakeTimeout());
      case _Deadline():
        return _atDeadline(approval);
      case _Resolved(:final data):
        final read = await _present(approval.token, approval.platform);
        if (read == null) return _hintOf(data);
        return _conclusive(read);
      case _Connection():
        final read = await _present(approval.token, approval.platform);
        return read == null ? null : _conclusive(read);
    }
  }

  /// An answer that ends the wait, or null when the request still waits. A
  /// server hiccup on a repeat is not an answer: the request is still there,
  /// and the next nudge asks again.
  static _Answer? _conclusive(_Answer read) => switch (read) {
    _Waiting() => null,
    _Closed(error: PairingFailed()) => null,
    _ => read,
  };

  /// This device's deadline came. The server is asked one last time; a
  /// request it still holds - its clock behind this one - is withdrawn on the
  /// way out, so no Allow pressed after this device stopped listening can
  /// pair a key nothing here knows. Expired either way, unless an Allow got
  /// there first.
  Future<_Answer> _atDeadline(_Approval approval) async {
    final read = await _present(approval.token, approval.platform);
    if (read is _Paired) return read;
    if (read is _Closed && read.error is! PairingFailed) return read;
    final last = await _withdraw(approval);
    if (last is _Paired) return last;
    logRepository.debug(target: this, message: 'pairing: no answer within the time, giving up');
    return const _Closed(PairingRefused(reason: PairRefusal.expired));
  }

  /// Withdraws the request and reads what it ended as - `cancelled`, or
  /// `expired` past the server's deadline, or the identity when an Allow got
  /// there first. Null when there was no channel to say it over.
  Future<_Answer?> _withdraw(_Approval approval) async {
    final withdrawn = await _bounded(_socket.cancelPairing(token: approval.token), _withdrawStep);
    if (withdrawn == null) return null;
    final reply = await _bounded(_socket.pair(token: approval.token, platform: approval.platform), _withdrawStep);
    return reply == null ? null : _read(reply);
  }

  /// Presents the token and reads the answer; null when it could not go out
  /// or no answer came within the socket's budget.
  Future<_Answer?> _present(String token, String platform) async {
    try {
      return _read(await _socket.pair(token: token, platform: platform));
    } on SocketUnavailableException {
      return null;
    }
  }

  /// [future], or null when it fails or outlives [within]. A late answer is
  /// dropped, and so is a late error - the timeout's own listener handles it.
  static Future<T?> _bounded<T>(Future<T> future, Duration within) async {
    try {
      return await future.timeout(within);
    } on Object {
      return null;
    }
  }

  /// What a `pair` reply says (contract §8A): the identity this device now
  /// speaks as, a request that waits, or how it ended.
  _Answer _read(CommandReply reply) {
    if (!reply.ok) {
      final refusal = _refusalFor(reply.errorCode);
      // A code that is not one of the two pairing refusals is not a refusal at
      // all - `internal`, `rate_limited`, a code this build predates. The
      // contract's evolution rule says treat it as `internal` and let the
      // person retry; calling it "this link cannot be used" would send them
      // hunting for a new invite over a server hiccup.
      return _Closed(refusal == null ? const PairingFailed() : PairingRefused(reason: refusal));
    }
    // An accepted reply this build cannot read is not a timeout. The channel
    // worked and the server answered - it answered in a shape this client does
    // not know, which is what a server speaking a protocol older or newer than
    // §8A looks like from here. Reporting it as a network error sends the person
    // to check their connection over something no connection can fix.
    final data = reply.data;
    if (data is! Map<String, dynamic>) return const _Closed(PairingFailed());
    final id = data['identity'];
    if (id is Map<String, dynamic>) return _Paired(_identityOf(id));
    final status = data['status'];
    if (status == 'pending') {
      return _Waiting(requestId: data['request_id'] is String ? data['request_id'] as String : '', expiresAt: _instant(data['expires_at']));
    }
    // The outcome a closed request recorded - the same words pair.resolved
    // carries, read the same way whichever of the two reached this device.
    return (status is String ? _closedAs(status) : null) ?? const _Closed(PairingFailed());
  }

  /// What a `pair.resolved` event says, taken at its word.
  _Answer? _hintOf(Map<String, dynamic> data) {
    final outcome = data['outcome'];
    if (outcome == 'allowed') {
      final id = data['identity'];
      return id is Map<String, dynamic> ? _Paired(_identityOf(id)) : null;
    }
    return outcome is String ? _closedAs(outcome) : null;
  }

  /// A request closed with [outcome], as the error that ends the wait.
  static _Answer? _closedAs(String outcome) => switch (outcome) {
    'denied' => const _Closed(PairingRefused(reason: PairRefusal.declined)),
    'expired' => const _Closed(PairingRefused(reason: PairRefusal.expired)),
    'cancelled' => const _Closed(PairingCancelled()),
    _ => null,
  };

  /// Unix seconds as an instant; null for anything that is not a number.
  static DateTime? _instant(Object? seconds) {
    if (seconds is! num || !seconds.isFinite) return null;
    return DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(), isUtc: true);
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
      // and spent a one-shot token, so the same link cannot be presented again
      // and the person has to issue another.
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
  ///
  /// [within] bounds the wait for the answer; the restart itself is always
  /// awaited.
  Future<IdentityHandshake> greet({Duration within = timeout}) async {
    // Captured BEFORE anything is torn down. The phase stream replays its
    // current value to a new listener, so on an already-connected socket the
    // first event carries the PREVIOUS connection's identity — including the
    // anonymous greeting the app makes at boot, whose `created` is always
    // true. Answering from that would route every returning person into
    // onboarding without the server having been asked about them at all.
    final generation = _socket.greetingGeneration;
    final pending = Completer<IdentityHandshake>();
    // The timer can fire while restart() is still bringing a slow path up -
    // through Tor that takes longer than the whole wait - and nobody is
    // listening yet. Marked handled so that is not an uncaught error; the
    // await below still receives it.
    pending.future.ignore();
    _pending = pending;
    _timer = Timer(within, () {
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

/// One request waiting for approval, and the single place its wait ends.
class _Approval {
  _Approval({required this.token, required this.platform});

  final String token;
  final String platform;

  /// Ends the wait: the identity, or the error that says how it ended. Marked
  /// handled so an outcome nobody awaits any more is not an uncaught error.
  final Completer<IdentityHandshake> result = Completer<IdentityHandshake>()..future.ignore();

  /// Set by a withdrawal under way. It reads the outcome itself, so nothing
  /// else acts on what it learns from then on.
  bool cancelling = false;

  bool get settled => result.isCompleted;

  /// The first answer wins; later ones describe a request already over.
  void settle(_Answer answer) {
    if (settled) return;
    switch (answer) {
      case _Paired(:final identity):
        result.complete(identity);
      case _Closed(:final error):
        result.completeError(error);
      case _Waiting():
        break;
    }
  }
}

/// What the server said about a token.
sealed class _Answer {
  const _Answer();
}

/// Paired: the identity this device now speaks as.
final class _Paired extends _Answer {
  const _Paired(this.identity);

  final IdentityHandshake identity;
}

/// The request waits for the device that issued the invite.
final class _Waiting extends _Answer {
  const _Waiting({required this.requestId, this.expiresAt});

  final String requestId;
  final DateTime? expiresAt;
}

/// No pairing, for the reason [error] carries.
final class _Closed extends _Answer {
  const _Closed(this.error);

  final Exception error;
}

/// Something that may have changed the answer to a request.
sealed class _Nudge {
  const _Nudge();
}

/// The `pair.resolved` event arrived.
final class _Resolved extends _Nudge {
  const _Resolved(this.data);

  final Map<String, dynamic> data;
}

/// A new connection opened.
final class _Connection extends _Nudge {
  const _Connection();
}

/// This device's own deadline came.
final class _Deadline extends _Nudge {
  const _Deadline();
}

/// The channel was refused for good.
final class _Terminal extends _Nudge {
  const _Terminal();
}
