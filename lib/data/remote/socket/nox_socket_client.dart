import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/socket/server_frame.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/app_config/server_limits.dart';
import 'package:nox_app/domain/model/session/server_identity.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/general/pairing/device_keys.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:rxdart/rxdart.dart';

/// The client half of the contract-v0 envelope: one socket, greeted once,
/// carrying correlated commands out and journal events in.
///
/// It knows the envelope and nothing above it — no chats, no messages. That
/// split is what lets its own tests drive correlation, backoff and phase
/// transitions over an in-memory channel, and what keeps the data sources
/// ignorant of reconnects.
///
/// Logging follows FR-019: phases, retries, failure codes and applied `seq`
/// are recorded; message bodies and user labels never are.
/// Registered only for the flavor that actually talks to a server: the mock
/// flavors have no socket, and registering one there would leave a dependency
/// with nothing to resolve.
@LazySingleton(env: [Environment.dev])
class NoxSocketClient {
  NoxSocketClient(this._factory, this._syncRepository);

  final SocketChannelFactory _factory;
  final SyncRepository _syncRepository;

  /// Backoff ladder, capped. Reset happens on a successful GREETING, not on a
  /// successful socket open: a half-open connection opens fine and then says
  /// nothing, and resetting there would spin the ladder forever.
  static const Duration _minBackoff = Duration(seconds: 1);
  static const Duration _maxBackoff = Duration(seconds: 30);

  /// Contract §5: a command with no reply in this window is a failure the
  /// caller may retry under the same idempotency key.
  static const Duration sendTimeout = Duration(seconds: 10);

  /// `rate_limited` is the only contract code marked repeatable (§2.1), so it
  /// is retried here and never shown to the user (FR-018).
  static const int _rateLimitRetries = 3;
  static const Duration _rateLimitPause = Duration(milliseconds: 500);

  final BehaviorSubject<SessionPhase> _phase = BehaviorSubject<SessionPhase>.seeded(SessionPhase.disconnected);
  final PublishSubject<ServerEvent> _events = PublishSubject<ServerEvent>();
  final Map<int, Completer<CommandReply>> _pending = <int, Completer<CommandReply>>{};
  final Random _random = Random();

  SocketConnection? _connection;
  StreamSubscription<dynamic>? _frames;
  Timer? _retryTimer;
  Duration _backoff = _minBackoff;
  int _nextId = 1;
  bool _started = false;

  /// Completes when the greeting has been answered on the CURRENT connection.
  ///
  /// The channel accepts writes the instant it is constructed, well before the
  /// handshake finishes, so without this gate a command issued in that window
  /// reaches the server before `session.hello` and is refused as malformed
  /// (contract §3, and the server enforces it) — surfacing to the user as a
  /// hard error rather than as "not connected yet".
  Completer<void>? _greeted;

  /// The cursor the server reported in the greeting. Catching up ends when an
  /// event with `seq >= _helloCursor` has been applied (contract §3).
  int _helloCursor = 0;

  Uri? _url;

  /// Asked at every greeting rather than handed once at start: the login
  /// derivation and the device id are read fresh so a sign-in or a logout in
  /// the same process greets as the right person, and the label is stated only
  /// on the greeting that follows a rename.
  Future<GreetingCredentials?> Function()? _credentialsProvider;

  /// Raised when the server turns out to be a different world than the one this
  /// device cached. The socket only reports it: emptying the local world belongs
  /// to whoever owns it, and a failure there must never cost the reconnect.
  void Function()? _onJournalChanged;

  /// The store identity from the last greeting (contract §3), mirrored from the
  /// persisted value for tests to read. The AUTHORITY is the persisted one:
  /// the case that actually happens is "the store was rebuilt and the app was
  /// restarted", and an in-memory field is null by then.
  String? journalId;

  /// Last greeting's identity and limits — the server is the authority on both.
  ServerIdentity? identity;

  /// Counts greetings applied on this client.
  ///
  /// A caller waiting for the answer to ITS greeting captures this first and
  /// refuses anything not above it. [phase] is a `BehaviorSubject`, so a fresh
  /// listener is handed the CURRENT phase immediately: on an already-live
  /// socket that would otherwise resolve the wait from the PREVIOUS
  /// connection's identity, before the restart had torn it down — which is
  /// exactly the guess the sign-in path exists to stop making.
  int greetingGeneration = 0;

  /// The challenge of the CURRENT connection, from the server's greeting.
  String _challenge = '';

  /// Called when the server does not recognise this device any more. Set by
  /// the session starter, which owns what happens next.
  void Function()? onUnauthenticated;
  ServerLimits? limits;

  Stream<SessionPhase> get phase => _phase.stream;
  SessionPhase get currentPhase => _phase.value;
  Stream<ServerEvent> get events => _events.stream;

  /// Opens the connection and keeps it open until [stop]. Safe to call twice.
  Future<void> start({
    required Uri url,
    Future<GreetingCredentials?> Function()? credentialsProvider,
    void Function()? onJournalChanged,
  }) async {
    _url = url;
    _credentialsProvider = credentialsProvider;
    _onJournalChanged = onJournalChanged;
    if (_started) return;
    _started = true;
    await _openOnce();
  }

  Future<void> stop() async {
    _started = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    // The ladder lives for the process and otherwise only resets on a
    // successful greeting. stop() is only ever called by a human action -
    // sign-in, logout, a channel restart - and after one of those the next
    // attempt must be prompt: a device that sat offline long enough to climb
    // to the ceiling would otherwise spend the whole sign-in wait without
    // making a single connection attempt.
    _backoff = _minBackoff;
    await _teardown(SessionPhase.disconnected);
  }

  /// Sends one command and waits for its reply.
  ///
  /// Throws [SocketUnavailableException] when there is no connection or the
  /// reply does not arrive within [sendTimeout]; callers turn that into the
  /// domain's `connection` failure, and the caller's idempotency key makes a
  /// retry safe even if the command did in fact reach the server.
  Future<CommandReply> send(String cmd, Map<String, dynamic> data) async {
    for (var attempt = 0; ; attempt++) {
      final reply = await _sendOnce(cmd, data);
      if (reply.errorCode != 'rate_limited' || attempt >= _rateLimitRetries) return reply;
      logRepository.debug(target: this, message: 'socket: rate limited, retrying: cmd=$cmd attempt=${attempt + 1}');
      await Future<void>.delayed(_rateLimitPause * (attempt + 1));
    }
  }

  /// Presents a pairing token, which is the ONE command allowed before the
  /// greeting: an unpaired device has nothing to sign the challenge with, so
  /// waiting for a handshake would make pairing impossible rather than awkward.
  ///
  /// Sent through [_sendOnce] with the greeting flag for exactly that reason —
  /// not because it is a greeting, but because it shares the one property that
  /// matters here: it must not wait for one.
  Future<CommandReply> pair({required String token, required String deviceKey, required String platform}) {
    return _sendOnce(isGreeting: true, 'pair', <String, dynamic>{'token': token, 'device_key': deviceKey, 'platform': platform});
  }

  /// Answers one waiting invite for a new person (contract §8B).
  ///
  /// Sent like any other command — the owner is greeted and signed; it is the
  /// device at the door that is not.
  Future<CommandReply> confirmPair({required String requestId, required bool approve}) {
    return send('person.confirm', <String, dynamic>{'request_id': requestId, 'approve': approve});
  }

  Future<CommandReply> _sendOnce(String cmd, Map<String, dynamic> data, {bool isGreeting = false}) async {
    if (!isGreeting) {
      final greeted = _greeted;
      if (greeted == null) throw const SocketUnavailableException('no connection');
      // Wait for the handshake rather than racing it — but never longer than a
      // command is allowed to take.
      try {
        await greeted.future.timeout(sendTimeout);
      } on TimeoutException {
        throw const SocketUnavailableException('handshake did not complete');
      }
    }
    final connection = _connection;
    if (connection == null) throw const SocketUnavailableException('no connection');
    final id = _nextId++;
    final completer = Completer<CommandReply>();
    _pending[id] = completer;
    connection.add(jsonEncode(<String, dynamic>{'id': id, 'cmd': cmd, 'data': data}));
    try {
      return await completer.future.timeout(sendTimeout);
    } on TimeoutException {
      _pending.remove(id);
      logRepository.debug(target: this, message: 'socket: command timed out: cmd=$cmd');
      throw const SocketUnavailableException('no reply within the send timeout');
    }
  }

  Future<void> _openOnce() async {
    final url = _url;
    if (!_started || url == null) return;
    _phase.add(SessionPhase.connecting);
    final greeted = Completer<void>();
    // Nobody may be waiting when the handshake fails, and an unobserved error
    // on a completer is reported as a crash. This marks it handled without
    // affecting callers that DO await it.
    greeted.future.ignore();
    _greeted = greeted;
    try {
      final connection = _factory.connect(url);
      _connection = connection;
      // Every connection gets a number, and every callback carries the one it
      // was born with. Closing a socket can FAIL - that is the whole reason
      // teardown absorbs its errors - and a socket that would not close keeps
      // delivering frames after the retry has opened its successor. Trusting
      // close() to stop them is trusting the thing that just failed; the
      // generation makes a leaked socket harmless instead of impossible.
      _connectionEpoch++;
      final epoch = _connectionEpoch;
      _frames = connection.frames.listen(
        (raw) => _onRawFrame(raw, epoch),
        onError: (Object e) {
          if (epoch == _connectionEpoch) _onDropped('stream error: ${e.runtimeType}');
        },
        onDone: () {
          if (epoch == _connectionEpoch) _onDropped('closed by peer');
        },
        cancelOnError: false,
      );
    } catch (e) {
      _onDropped('connect failed: ${e.runtimeType}');
    }
  }

  /// Counts connections, so a frame can say which one it came from.
  int _connectionEpoch = 0;

  /// Consecutive greetings this client could not read. Reset by a successful
  /// one, because a peer that greets properly once is not the broken case.
  int _greetFailures = 0;

  /// How many of those before the channel is called unusable rather than
  /// merely down. Small: a deterministic fault repeats immediately, and the
  /// backoff ladder has already spread these attempts over half a minute.
  static const int _maxGreetFailures = 5;

  void _onRawFrame(dynamic raw, int epoch) {
    // From a connection we have already moved on from. It may still be open -
    // see the generation counter above - and anything it says now would be
    // answered on behalf of a socket nobody is using.
    if (epoch != _connectionEpoch) return;
    if (raw is! String) return; // binary frames are not part of contract v0
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      logRepository.debug(target: this, message: 'socket: undecodable frame dropped');
      return;
    }
    final frame = ServerFrame.parse(json);
    switch (frame) {
      case SrvGreeting(:final challenge):
        // Kept per connection: a signature made over one connection's challenge
        // is useless on the next, which is what makes replay pointless.
        _challenge = challenge;
        unawaited(_greet());
      case CommandReply(:final id):
        _pending.remove(id)?.complete(frame);
      case ServerEvent():
        _events.add(frame);
        _maybeGoLive(frame.seq);
      case null:
        break; // unknown frame kind — v0 evolves, ignoring is the rule
    }
  }

  /// Sends the greeting: our sync point, and the label this device remembers.
  /// The reply is authoritative for identity, limits and the catch-up cursor.
  ///
  /// FIRST connection omits `since` entirely (contract §3). Server seqs start
  /// at 1, so a stored cursor of 0 already means "nothing was ever applied" —
  /// no extra state is needed to tell the two apart. Sending `since: 0` instead
  /// would ask the server to replay its ENTIRE journal, which is exactly what
  /// happens after the epoch wipe puts a device back to zero.
  Future<void> _greet() async {
    try {
      final since = await _syncRepository.getCursor();
      final firstEver = since == 0;
      final provider = _credentialsProvider;
      final credentials = provider == null ? const GreetingCredentials() : await provider();
      if (credentials == null) {
        // The provider could not tell who we are - a transient storage failure.
        // Greeting anyway would send an unsigned hello, which the server
        // refuses; wait and re-read instead.
        await _teardown(SessionPhase.disconnected);
        _scheduleRetry();
        return;
      }
      if (credentials.unpaired) {
        // Held open, NOT torn down: this is the window `pair` runs in, and it
        // is the one command allowed before a greeting. Nothing else can be
        // sent - every other command waits on the greeting that will not come
        // until pairing has happened.
        logRepository.debug(target: this, message: 'socket: not paired yet, holding the connection open for pairing');
        return;
      }
      String? deviceKey;
      String? signature;
      final seed = credentials.deviceSeed;
      if (seed != null && seed.isNotEmpty && _challenge.isNotEmpty) {
        try {
          deviceKey = await DeviceKeys.publicKey(seed);
          signature = await DeviceKeys.signChallenge(seed: seed, challenge: _challenge);
        } on Object catch (e) {
          // Fail CLOSED. Greeting unsigned would ask the server to accept us
          // without proof - and if it ever did, this path would be the way in.
          // A challenge that will not decode is a broken peer; tear down and
          // let the reconnect ladder retry.
          logRepository.debug(target: this, message: 'socket: could not sign the challenge: ${e.runtimeType}');
          await _teardown(SessionPhase.disconnected);
          _scheduleRetry();
          return;
        }
      }
      final reply = await _sendOnce(isGreeting: true, 'session.hello', <String, dynamic>{
        'schema': 1,
        if (!firstEver) 'since': since,
        // Stated only after a rename: a greeting that repeats a cached name
        // would push it back over a rename made from another device.
        'label': ?credentials.label,
        // The public half and a signature over the challenge - never the seed.
        // Both are always present here: a device that has not paired yet does
        // not reach this point at all, because there is no anonymous greeting
        // any more and the server refuses one.
        'device_key': ?deviceKey,
        'signature': ?signature,
      });
      if (!reply.ok) {
        logRepository.debug(target: this, message: 'socket: greeting refused: code=${reply.errorCode}');
        // A version mismatch or a malformed greeting is a programmer error, not
        // a blip: the contract marks both non-repeatable (§2.1). Retrying would
        // spin forever against a server that will never accept us.
        if (reply.errorCode == 'unauthenticated') {
          // Revoked, or a server whose store was rebuilt. The device cannot
          // tell those apart and must not: both mean "this is not my server any
          // more". Retrying would spin forever against a peer that will keep
          // refusing, so the session is torn down and the app is told.
          //
          // Only the CALLBACK is guarded, because only it can fail: `_teardown`
          // absorbs its own errors by construction, and that invariant is
          // stated in its doc comment rather than assumed here. A throw from
          // the callback must not reach the catch-all at the end of this
          // method, which retries - that would undo the decision this branch
          // exists to make and put a revoked device back in a refusal loop.
          await _teardown(SessionPhase.unsupported);
          try {
            onUnauthenticated?.call();
          } on Object catch (e, st) {
            logRepository.error(target: this, error: 'unauthenticated handler failed: ${e.runtimeType}', stackTrace: st);
          }
          return;
        }
        final terminal = reply.errorCode == 'unsupported_schema' || reply.errorCode == 'invalid_request';
        await _teardown(terminal ? SessionPhase.unsupported : SessionPhase.disconnected);
        if (!terminal) _scheduleRetry();
        return;
      }
      final data = reply.data ?? const <String, dynamic>{};

      // Checked BEFORE anything else is taken from the reply, and long before
      // the first replay frame: a rebuilt store that has already overtaken our
      // mark is indistinguishable from a healthy one by cursor alone, so we
      // would apply strangers' events under numbers we already believe we hold.
      final serverJournal = data['journal_id'] as String?;
      final knownJournal = await _syncRepository.getJournal();
      // A device holding a cursor but no remembered journal learned that cursor
      // from a world that predates this field — every install from before this
      // release. Treating that as "no divergence" would opt the check out of
      // the one transition it exists for: the store is rebuilt (this release
      // forces it), the device keeps a cursor above the new journal, and it
      // never receives anything again. An empty local world wipes nothing.
      final diverged = serverJournal != null && (knownJournal == null ? since > 0 : serverJournal != knownJournal);
      if (diverged) {
        logRepository.debug(target: this, message: 'socket: server journal changed, local world is stale');
        // Recorded FIRST, and it outlives the wipe it is about to trigger:
        // leaving the old name behind would make the next greeting look like
        // another change and wipe again, on every reconnect, forever.
        await _syncRepository.setJournal(serverJournal);
        journalId = serverJournal;
        await _teardown(SessionPhase.disconnected);
        // Report, then retry regardless of what the owner of the local world
        // does with the news — a throw over there must not strand the socket.
        try {
          _onJournalChanged?.call();
        } on Object catch (e, s) {
          logRepository.error(target: this, error: e, stackTrace: s);
        }
        _scheduleRetry();
        return;
      }
      if (serverJournal != null) {
        if (knownJournal != serverJournal) await _syncRepository.setJournal(serverJournal);
        journalId = serverJournal;
      }

      // Any NUMBER is accepted: JSON round-tripped through a float parser makes
      // 1042 arrive as 1042.0, and refusing that would retry for ever with
      // nothing on screen saying why. Only a truly absent or non-numeric cursor
      // is a reconnect - substituting 0 would make `since >= _helloCursor` true
      // on the next line, declaring catch-up complete before a single replay
      // frame was applied.
      final rawCursor = data['cursor'];
      // TERMINAL, not a retry. A greeting without a usable cursor is a peer
      // that does not speak this contract, and reconnecting to it produces the
      // same reply for ever - an app stuck on "connecting" with nothing on
      // screen saying why. `unsupported` is how the other non-repeatable
      // refusals are reported, and this is one of them.
      //
      // `isFinite` because NaN and Infinity are both `num`: `toInt()` throws on
      // either, and a guard that lets through the two values it cannot convert
      // is not a guard.
      if (rawCursor is! num || !rawCursor.isFinite) {
        logRepository.debug(target: this, message: 'socket: greeting carried no usable cursor');
        await _teardown(SessionPhase.unsupported);
        return;
      }
      _helloCursor = rawCursor.toInt();
      final id = data['identity'];
      if (id is! Map<String, dynamic>) {
        // Stage 1 always states who connected. A reply without it is not a
        // greeting we can act on, and treating it as success would leave the
        // previous connection's person in place (see the teardown reset).
        logRepository.debug(target: this, message: 'socket: greeting carried no identity');
        await _teardown(SessionPhase.disconnected);
        _scheduleRetry();
        return;
      }
      identity = ServerIdentity(
        // Read, not cast, for the same reason as the two booleans below: a
        // wrong-typed field is worth ignoring, never worth wedging the channel.
        id: id['id'] is String ? id['id'] as String : '',
        label: id['label'] is String ? id['label'] as String : '',
        // Absent stays absent: it means "outcome not stated", which is neither
        // outcome, and the sign-in path must not be handed a guess.
        //
        // Type-checked rather than cast. `as bool?` throws on anything that is
        // not a bool - a peer sending `1` or `"true"` - and the throw escapes
        // _greet(), which catches only SocketUnavailableException and is called
        // through unawaited(): no teardown, no retry, no completed greeting.
        // The socket then hangs until the process restarts. A malformed field
        // is worth ignoring, never worth wedging the channel for.
        created: id['created'] is bool ? id['created'] as bool : null,
        // Same rule for ownership, and for a sharper reason: a server that does
        // not state it is not saying "no". Reading a missing field as false
        // would strip the badge from an owner talking to an older build.
        isOwner: id['owner'] is bool ? id['owner'] as bool : null,
      );
      greetingGeneration++;
      final lim = data['limits'];
      if (lim is Map<String, dynamic>) {
        // `num`, like the cursor above and for the same reason: a JSON layer
        // that round-trips numbers through a float sends 65536.0, and treating
        // that as unreadable would silently install the contract default in
        // place of the limit the server actually stated - so the composer's
        // pre-flight check would block messages the server accepts, or pass
        // ones it rejects.
        limits = ServerLimits(
          maxMessageBytes: _limit(lim['max_message_bytes'], ServerLimits.contractDefaults.maxMessageBytes),
          maxAttachmentBytes: _limit(lim['max_attachment_bytes'], ServerLimits.contractDefaults.maxAttachmentBytes),
          maxFrameBytes: _limit(lim['max_frame_bytes'], ServerLimits.contractDefaults.maxFrameBytes),
        );
      }
      // The ladder resets HERE — a greeting is the first proof the peer is real.
      _backoff = _minBackoff;
      _greetFailures = 0;
      // Commands may flow from here: the server has accepted this connection.
      if (_greeted?.isCompleted == false) _greeted!.complete();
      _phase.add(SessionPhase.catchingUp);
      logRepository.debug(target: this, message: 'socket: greeted: first=$firstEver cursor=$_helloCursor');
      if (firstEver) {
        // No replay was requested, so the reply's cursor becomes our starting
        // point and the bootstrap happens through ordinary list reads (§3).
        await _syncRepository.advanceCursor(_helloCursor);
        _phase.add(SessionPhase.live);
      } else if (since >= _helloCursor) {
        // Already level with the server: the catch-up rule resolves instantly.
        _phase.add(SessionPhase.live);
      }
    } on SocketUnavailableException {
      await _teardown(SessionPhase.disconnected);
      _scheduleRetry();
    } on Object catch (e, st) {
      // Everything else, and deliberately so. This method runs through
      // `unawaited()`, so any escaping throw becomes an unhandled async error:
      // no teardown, no retry, `_greeted` never completed - the channel is dead
      // for the life of the process and nothing says why. A malformed field in
      // a reply is worth a reconnect; it is never worth that.
      //
      // The field-by-field type checks in the parse above help, but they can
      // only cover the fields somebody remembered. This covers the rest.
      // The TYPE and where it happened, deliberately not the message. A
      // TypeError quotes the offending value, and the value here can be a
      // person's display name - Principle I keeps names out of logs whether or
      // not they also travelled on the wire.
      //
      // One line, like every other failure branch in this method: the stack
      // trace carries the rest, and a flapping peer should not double this
      // file's log volume for a single event.
      logRepository.error(target: this, error: 'greeting reply unreadable: ${e.runtimeType}', stackTrace: st);
      // Bounded. A malformed frame can be a blip, so the first few attempts
      // retry - but a deterministic fault produces the same throw on every one
      // of them, and an unbounded loop leaves the app "connecting" for ever
      // with nothing to show the person. After the ladder has been climbed a
      // few times this is reported the way the other non-repeatable failures
      // are, so a surface can say it will not work.
      _greetFailures++;
      if (_greetFailures >= _maxGreetFailures) {
        await _teardown(SessionPhase.unsupported);
        return;
      }
      await _teardown(SessionPhase.disconnected);
      _scheduleRetry();
    }
  }

  /// One limit from the greeting, or the contract default when the server did
  /// not state a usable one.
  ///
  /// "Usable" means positive. A stated `0` is not a limit the composer can work
  /// with - its pre-flight check would refuse every message the person types,
  /// with nothing on screen explaining why - and a negative one is worse. The
  /// contract default is one comparison away, so an unusable value is treated
  /// like an absent one rather than installed verbatim.
  static int _limit(Object? raw, int fallback) {
    if (raw is! num) return fallback;
    final value = raw.toInt();
    return value > 0 ? value : fallback;
  }

  /// The catch-up rule: applied `seq >= cursor` means replay is behind us.
  void _maybeGoLive(int seq) {
    if (_phase.value == SessionPhase.catchingUp && seq >= _helloCursor) {
      _phase.add(SessionPhase.live);
      logRepository.debug(target: this, message: 'socket: caught up: seq=$seq');
    }
  }

  void _onDropped(String reason) {
    if (_phase.value != SessionPhase.disconnected) logRepository.debug(target: this, message: 'socket: dropped $reason');
    unawaited(_teardown(SessionPhase.disconnected));
    _scheduleRetry();
  }

  /// Never throws, and always finishes the reset.
  ///
  /// Both awaits below can fail - closing a socket that is already gone throws
  /// on several platforms, and `_onDropped` runs on exactly that path. When
  /// they did, everything after them was skipped: the subscription and the
  /// connection stayed live, pending callers were never failed, and `identity`
  /// survived into the next connection - which is what this method's own
  /// comment says must not happen. The retry then opened a SECOND socket while
  /// the old frames kept arriving.
  ///
  /// Guarding at the call sites could not fix that; only finishing the reset
  /// can. So the failures are absorbed here and the state below always runs.
  Future<void> _teardown(SessionPhase next) async {
    try {
      await _frames?.cancel();
    } on Object catch (e) {
      logRepository.debug(target: this, message: 'socket: frame subscription would not cancel (${e.runtimeType})');
    }
    _frames = null;
    try {
      await _connection?.close();
    } on Object catch (e) {
      logRepository.debug(target: this, message: 'socket: connection would not close (${e.runtimeType})');
    }
    _connection = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(const SocketUnavailableException('connection lost'));
    }
    _pending.clear();
    // Callers waiting on the handshake must not hang past the drop.
    if (_greeted?.isCompleted == false) _greeted!.completeError(const SocketUnavailableException('connection lost'));
    _greeted = null;
    // What the greeting declared belongs to the connection that declared it.
    // Kept across a drop, `identity` would let a sign-in that timed out adopt
    // the PREVIOUS connection's person; `limits` would govern a pre-flight
    // check for a peer we are no longer talking to. The journal id is the one
    // exception: it names the world our cache came from and outlives the
    // socket by design.
    identity = null;
    limits = null;
    // Guarded too: dispose() closes the subject while an unawaited greeting can
    // still be in flight, and adding to a closed subject throws. Nobody is
    // listening by then, so there is nothing to tell and nothing to fail.
    try {
      if (_phase.value != next) _phase.add(next);
    } on Object {
      // Closed. The teardown itself is done, which is what mattered.
    }
  }

  void _scheduleRetry() {
    if (!_started || _retryTimer != null) return;
    final wait = _withJitter(_backoff);
    logRepository.debug(target: this, message: 'socket: reconnecting: in=${wait.inMilliseconds}ms');
    _retryTimer = Timer(wait, () {
      _retryTimer = null;
      unawaited(_openOnce());
    });
    final next = _backoff * 2;
    _backoff = next > _maxBackoff ? _maxBackoff : next;
  }

  /// ±20% so a fleet of devices does not stampede a recovering server.
  Duration _withJitter(Duration base) {
    final spread = (base.inMilliseconds * 0.2).round();
    final delta = spread == 0 ? 0 : _random.nextInt(spread * 2) - spread;
    return Duration(milliseconds: base.inMilliseconds + delta);
  }

  @disposeMethod
  Future<void> dispose() async {
    await stop();
    await _phase.close();
    await _events.close();
  }
}

/// What a greeting states about who is connecting (contract §3). Every field is
/// optional by contract: a connection presenting none of them is served as a
/// one-off, which is what keeps hand tools and the live probe working.
class GreetingCredentials {
  const GreetingCredentials({this.deviceSeed, this.label, this.unpaired = false});

  /// This install has not paired yet, so there is nothing to greet with.
  ///
  /// The connection is still needed - `pair` is the one command allowed before
  /// a greeting - so the socket stays open and simply does not greet. Greeting
  /// anyway would be an unsigned hello, which the server refuses, and the
  /// refusal reads as a revocation.
  const GreetingCredentials.unpaired() : deviceSeed = null, label = null, unpaired = true;

  /// This device's key seed. The socket derives the public half for
  /// `device_key` and signs the challenge with it — the seed itself never
  /// reaches the wire, and neither does anything derived from a login
  /// identifier, which no longer exists.
  final String? deviceSeed;

  /// Present only on the greeting that follows a rename.
  final String? label;

  /// See [GreetingCredentials.unpaired].
  final bool unpaired;
}
