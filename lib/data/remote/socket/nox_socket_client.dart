import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/channel/channel_failure.dart';
import 'package:nox_app/data/remote/socket/server_addresses_parser.dart';
import 'package:nox_app/data/remote/socket/server_frame.dart';
import 'package:nox_app/data/remote/socket/socket_channel_factory.dart';
import 'package:nox_app/data/remote/socket/socket_target_provider.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/app_config/server_limits.dart';
import 'package:nox_app/domain/model/connection/server_addresses.dart';
import 'package:nox_app/domain/model/session/server_identity.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
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
  NoxSocketClient(this._factory, this._syncRepository)
    : _pathChoiceBudget = defaultPathChoiceBudget,
      _minBackoff = defaultMinBackoff,
      _maxBackoff = defaultMaxBackoff;

  /// The same client with its waits shortened, so a test can watch a bound
  /// run out or a ladder climb without waiting minutes for it.
  @visibleForTesting
  NoxSocketClient.forTest(
    this._factory,
    this._syncRepository, {
    this._pathChoiceBudget = defaultPathChoiceBudget,
    this._minBackoff = defaultMinBackoff,
    this._maxBackoff = defaultMaxBackoff,
  });

  final SocketChannelFactory _factory;
  final SyncRepository _syncRepository;

  /// Backoff ladder, capped. Reset happens on a successful GREETING, not on a
  /// successful socket open: a half-open connection opens fine and then says
  /// nothing, and resetting there would spin the ladder forever.
  static const Duration defaultMinBackoff = Duration(seconds: 1);
  static const Duration defaultMaxBackoff = Duration(seconds: 30);
  final Duration _minBackoff;
  final Duration _maxBackoff;

  /// How long an attempt waits for its path to be chosen (phase 042). The
  /// choice is bounded in parts - the direct probe, the wait for Tor to be
  /// ready - but not in everything it awaits: a Tor client that never
  /// finished starting held the attempt, and with it every attempt after it,
  /// until the app was relaunched. Past this the choice counts as "no path"
  /// and the ladder asks again. Above the probe plus Tor's readiness budget
  /// (5 s + 90 s), so it never cuts a choice that is merely slow.
  static const Duration defaultPathChoiceBudget = Duration(seconds: 120);
  final Duration _pathChoiceBudget;

  /// Contract §5: a command with no reply in this window is a failure the
  /// caller may retry under the same idempotency key.
  static const Duration sendTimeout = Duration(seconds: 10);

  /// How long a command waits for the greeting while the slow path comes up:
  /// Tor's bring-up budget, one onion dial and the greeting itself (research
  /// decision 5). Without it a command sent at the start of a Tor bring-up
  /// would fail on [sendTimeout] while the path was still on its way (FR-023).
  static const Duration slowPathBudget = Duration(seconds: 145);

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
  late Duration _backoff = _minBackoff;
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

  /// The highest journal `seq` seen on the CURRENT connection.
  ///
  /// The replay follows the greeting reply on the wire, and a burst of frames
  /// can be delivered before the code awaiting that reply resumes - more so
  /// through Tor, which hands bytes over in cells. Events seen in that window
  /// arrive while the phase is still `connecting`, so the catch-up rule never
  /// looks at them; without this the socket would sit in `catchingUp` until
  /// the next live event, and nothing that waits for `live` - the outgoing
  /// queue among them - would move.
  int _seenSeq = 0;

  /// Asked for an address before every attempt (phase 040).
  SocketTargetProvider? _targets;

  /// The address the current attempt dialled, for as long as it is current.
  Uri? _dialled;

  /// Counts attempts. Choosing a path can take long - a Tor bring-up is the
  /// better part of two minutes - and a stop, a restart or a switch in the
  /// meantime makes the attempt that was choosing a stale one.
  int _attempt = 0;

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

  /// Called when the server does not recognise this device any more. Set by
  /// the session starter, which owns what happens next.
  void Function()? onUnauthenticated;
  ServerLimits? limits;

  /// Where the server can be found, as the last greeting stated it (contract
  /// §3, phase 039). Null before a greeting, and from a server older than 039.
  ServerAddresses? addresses;

  /// Whether the server reads what phase 039 added to the wire,
  /// `device.setAccessKey` among it. The greeting carrying `addresses` is that
  /// flag (contract §2.1).
  bool get supportsAccessKeys => addresses != null;

  /// The address of the current connection; null between connections.
  Uri? get currentUrl => _connection == null ? null : _dialled;

  Stream<SessionPhase> get phase => _phase.stream;
  SessionPhase get currentPhase => _phase.value;
  Stream<ServerEvent> get events => _events.stream;

  /// Opens the connection and keeps it open until [stop]. Safe to call twice.
  ///
  /// [targets] is asked for an address before every attempt; [url] is the
  /// shorthand for one address that never changes. Exactly one is given.
  Future<void> start({
    Uri? url,
    SocketTargetProvider? targets,
    Future<GreetingCredentials?> Function()? credentialsProvider,
    void Function()? onJournalChanged,
  }) async {
    assert((url == null) != (targets == null), 'either a url or a target provider');
    _targets = targets ?? FixedSocketTarget(url!);
    _credentialsProvider = credentialsProvider;
    _onJournalChanged = onJournalChanged;
    if (_started) return;
    _started = true;
    // Not awaited. Choosing a path can take a while - the direct addresses are
    // probed first, and Tor may come up behind them - and nothing about
    // starting needs that choice made. The app's first screen waits on this
    // method; a person away from home would otherwise look at the launch
    // screen for as long as Tor takes.
    unawaited(_openOnce());
  }

  Future<void> stop() async {
    _started = false;
    _attempt++;
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

  /// Drops the current connection and dials again at once, asking the target
  /// provider afresh (phase 040).
  ///
  /// How the path selector moves the socket to a path it has just verified,
  /// and how a return from the background skips the ladder. Lossless by the
  /// protocol rather than by holding two sockets: the replay resumes from the
  /// cursor, a duplicate falls to its `seq`, and a resent command is idempotent
  /// under its own key (FR-004).
  ///
  /// A terminal phase stays terminal: nothing about a refused onion key or an
  /// unsupported server changes because the network did.
  Future<void> reconnect() async {
    if (!_started || _phase.value.isTerminal) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    _backoff = _minBackoff;
    await _teardown(SessionPhase.disconnected);
    await _openOnce();
  }

  /// Sends one command and waits for its reply.
  ///
  /// Throws [SocketUnavailableException] when there is no connection or the
  /// reply does not arrive within [sendTimeout]; callers turn that into the
  /// domain's `connection` failure, and the caller's idempotency key makes a
  /// retry safe even if the command did in fact reach the server.
  ///
  /// [waitForConnection] false is for reads the screen can answer from its
  /// cache. Without a greeted connection they fail at once instead of waiting
  /// for one - through Tor that wait is up to [slowPathBudget], and it kept
  /// the chats and messages already on the device off the screen for all of
  /// it. The screens read again once the channel is live.
  Future<CommandReply> send(String cmd, Map<String, dynamic> data, {bool waitForConnection = true}) async {
    for (var attempt = 0; ; attempt++) {
      // Checked before every attempt, not only the first: the connection can be
      // replaced during the pause after `rate_limited`, and the retry would
      // otherwise wait for the next greeting after all.
      if (!waitForConnection && _greeted?.isCompleted != true) throw const SocketUnavailableException('not connected');
      final reply = await _sendOnce(cmd, data);
      if (reply.errorCode != 'rate_limited' || attempt >= _rateLimitRetries) return reply;
      logRepository.debug(target: this, message: 'socket: rate limited, retrying: cmd=$cmd attempt=${attempt + 1}');
      await Future<void>.delayed(_rateLimitPause * (attempt + 1));
    }
  }

  /// Presents a pairing token, which is the ONE command allowed before the
  /// greeting: the server does not know this device's key yet, so a greeting
  /// would be refused, and waiting for one would make pairing impossible
  /// rather than awkward. The key itself is not in the command - the server
  /// takes it from the connection, whose Eidolon check this device has just
  /// passed with it (phase 044). And nothing goes out before the channel has
  /// verified the server's key: a machine with another key never sees the
  /// token.
  ///
  /// Sent through [_sendOnce] with the greeting flag for exactly that reason —
  /// not because it is a greeting, but because it shares the one property that
  /// matters here: it must not wait for one.
  ///
  /// [accessKey] - the public half of this device's onion access key - goes
  /// with every pairing (phase 040): a server that does not know the field
  /// skips it, and one that does registers the key in the same transaction,
  /// so a device that paired through Tor keeps its way in once the invite's
  /// one-time key is gone (contract §2.1, §8A).
  ///
  /// A connection lost under the pairing does not lose the pairing: the token
  /// is presented again on the next connection, within ONE budget for the
  /// whole attempt. That is safe whatever became of the first presentation -
  /// the server answers the same token from the same device with the same
  /// identity (contract §8A) - and it is what keeps a dial that ran out its
  /// time through Tor, or a network change mid-pairing, from sending the
  /// person off to try again by hand.
  Future<CommandReply> pair({required String token, required String platform, String? accessKey}) async {
    final data = <String, dynamic>{'token': token, 'platform': platform, 'access_key': ?accessKey};
    final waited = Stopwatch()..start();
    var slow = false;
    // The slow budget from the moment the slow path shows, and kept: between
    // connections the socket no longer knows which way the last one went.
    Duration left() {
      slow = slow || _slowPath;
      return (slow ? slowPathBudget : sendTimeout) - waited.elapsed;
    }

    while (true) {
      final connection = await _awaitConnection(left: left);
      try {
        return await _sendOnce(isGreeting: true, via: connection, 'pair', data, left: left);
      } on SocketUnavailableException {
        if (!_started || left() <= Duration.zero) rethrow;
        logRepository.debug(target: this, message: 'socket: the connection carrying pair went away, presenting it again');
      }
    }
  }

  /// [via] pins the command to one connection: the greeting belongs to the
  /// connection it answers, so it must never wait for - or go out on - the
  /// next one. [left] is what remains of a budget the caller spans over
  /// several sends.
  Future<CommandReply> _sendOnce(
    String cmd,
    Map<String, dynamic> data, {
    bool isGreeting = false,
    SocketConnection? via,
    Duration Function()? left,
  }) async {
    if (!isGreeting) await _awaitGreeting();
    final connection = via ?? (isGreeting ? await _awaitConnection() : _connection);
    if (connection == null || (via != null && !identical(_connection, via))) {
      throw const SocketUnavailableException('no connection');
    }
    // `pair` goes out before any greeting - possibly before the connection
    // itself is up, the connection holding the frame meanwhile. Through Tor
    // that dial alone can outlast the short timeout (research decision 5), and
    // a pairing that timed out while its frame was still on the way would tell
    // the person to try again over a pairing that is about to succeed.
    final wait = left?.call() ?? (isGreeting && _slowPath ? slowPathBudget : sendTimeout);
    if (wait <= Duration.zero) throw const SocketUnavailableException('no time left');
    final id = _nextId++;
    final completer = Completer<CommandReply>();
    _pending[id] = completer;
    connection.add(jsonEncode(<String, dynamic>{'id': id, 'cmd': cmd, 'data': data}));
    try {
      return await completer.future.timeout(wait);
    } on TimeoutException {
      _pending.remove(id);
      logRepository.debug(target: this, message: 'socket: command timed out: cmd=$cmd');
      throw const SocketUnavailableException('no reply within the send timeout');
    }
  }

  /// Waits for the handshake rather than racing it - but never longer than a
  /// command is allowed to take, unless the slow path is coming up.
  ///
  /// The budget is looked at again whenever the short one runs out: a command
  /// sent while the direct addresses are being tried cannot know yet that Tor
  /// will follow, and it must not fail on the short timeout once it has
  /// (FR-023). It never waits past [slowPathBudget] in all.
  Future<void> _awaitGreeting() async {
    final waited = Stopwatch()..start();
    while (true) {
      final greeted = _greeted;
      if (greeted == null) throw const SocketUnavailableException('no connection');
      final budget = _slowPath ? slowPathBudget : sendTimeout;
      final left = budget - waited.elapsed;
      if (left <= Duration.zero) throw const SocketUnavailableException('handshake did not complete');
      try {
        await greeted.future.timeout(left);
        return;
      } on TimeoutException {
        if (!_slowPath) throw const SocketUnavailableException('handshake did not complete');
      }
    }
  }

  /// Waits for the current attempt to have a connection - for the commands
  /// sent before any greeting, `pair` above all.
  ///
  /// A started socket can be between connections: choosing a path, or a
  /// restart that superseded the attempt a caller was counting on. Failing at
  /// once there told the person their pairing did not work while the channel
  /// was a moment from opening. Bounded like the greeting wait: the short
  /// timeout, or the slow-path budget while Tor comes up - or by [left], a
  /// caller's own budget spanning several connections.
  Future<SocketConnection> _awaitConnection({Duration Function()? left}) async {
    final waited = Stopwatch()..start();
    final remaining = left ?? () => (_slowPath ? slowPathBudget : sendTimeout) - waited.elapsed;
    while (true) {
      final connection = _connection;
      if (connection != null) return connection;
      if (!_started) throw const SocketUnavailableException('no connection');
      final wait = remaining();
      if (wait <= Duration.zero) throw const SocketUnavailableException('no connection');
      try {
        await _opened.stream.first.timeout(wait);
      } on TimeoutException {
        // Looked at again: the slow path may have shown meanwhile.
      }
    }
  }

  /// One event per connection this client opens.
  final StreamController<void> _opened = StreamController<void>.broadcast();

  /// Whether the attempt in progress is bringing up the slow path: the target
  /// provider is starting Tor, or the address being dialled is an onion one.
  bool get _slowPath {
    if (_targets?.bringingUpSlowPath ?? false) return true;
    final dialled = _dialled;
    return dialled != null && isOnionUrl(dialled);
  }

  Future<void> _openOnce() async {
    final targets = _targets;
    if (!_started || targets == null) return;
    final attempt = ++_attempt;
    _dialled = null;
    _phase.add(SessionPhase.connecting);
    final greeted = Completer<void>();
    // Nobody may be waiting when the handshake fails, and an unobserved error
    // on a completer is reported as a crash. This marks it handled without
    // affecting callers that DO await it.
    greeted.future.ignore();
    _greeted = greeted;
    Uri? url;
    try {
      url = await targets.nextTarget().timeout(_pathChoiceBudget);
    } on TimeoutException {
      // Abandoned, not failed by the path: the late answer is dropped by the
      // attempt check below - this attempt has moved on by then.
      logRepository.debug(target: this, message: 'socket: choosing a path took over ${_pathChoiceBudget.inSeconds} s, abandoned');
    } on Object catch (e, st) {
      // A path that cannot be chosen is a path that is not there; the ladder
      // asks again. Never a reason for the socket to stop trying.
      logRepository.error(target: this, error: 'choosing a path failed: ${e.runtimeType}', stackTrace: st);
    }
    // Stopped, restarted or switched while the path was being chosen.
    if (attempt != _attempt || !_started) return;
    if (url == null) {
      _onDropped('no path to the server');
      return;
    }
    final target = url;
    _dialled = target;
    try {
      final connection = _factory.connect(target);
      _connection = connection;
      _opened.add(null);
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
          if (epoch != _connectionEpoch) return;
          // The channel's own verdict, found inside whatever the WebSocket
          // wrapped it in. Every kind but one is a failed attempt like a drop:
          // the network, a timeout, TLS, a peer that does not speak the
          // channel or a machine in the middle (`protocol`), Tor. None of
          // them is ever a reason to log out.
          final failure = channelFailureOf(e);
          if (failure == ChannelFailure.wrongServer) {
            _wrongServer(target);
            return;
          }
          _onDropped('stream error: ${failure?.name ?? e.runtimeType}');
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

  /// The machine at [url] proved a key other than the one the pairing link
  /// named (phase 044: the channel's `wrongServer`).
  ///
  /// At an ONION address that is not this person's server (FR-011): nobody
  /// can answer there without the onion service's keys, so the server was
  /// reinstalled or the machine replaced. Terminal, and terminal in a very
  /// particular way: no reconnect ladder, because nothing about the answer
  /// will change on its own - until the person asks for Try again or pairs
  /// anew; and NOT through [onUnauthenticated], which ends in a forced logout
  /// that wipes every message on the device (FR-012). Sending a stranger's
  /// key down that path would let anyone able to answer at the address erase
  /// this person's data on every device they own.
  ///
  /// At a DIRECT address it means "not home": addresses are reused, and on
  /// another network the same one is somebody else's machine. Nothing is
  /// shown; the address is reported and the socket goes on to the next path.
  void _wrongServer(Uri url) {
    if (isOnionUrl(url)) {
      logRepository.debug(target: this, message: 'socket: the server behind the onion address proved another key');
      unawaited(_teardown(SessionPhase.serverMismatch));
      return;
    }
    logRepository.debug(target: this, message: 'socket: a direct address answered with another key, so it does not lead home now');
    try {
      _targets?.reportWrongServer(url);
    } on Object catch (e, st) {
      logRepository.error(target: this, error: 'wrong-server report failed: ${e.runtimeType}', stackTrace: st);
    }
    _onDropped('another key at a direct address');
  }

  /// Counts connections, so a frame can say which one it came from.
  int _connectionEpoch = 0;

  static const Duration _closeBound = Duration(seconds: 2);

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
      case SrvGreeting():
        // Answered on the connection that asked: the greeting belongs to it.
        final connection = _connection;
        if (connection != null) unawaited(_greet(connection: connection, epoch: epoch));
      case CommandReply(:final id):
        _pending.remove(id)?.complete(frame);
      case ServerEvent():
        if (frame.seq > _seenSeq) _seenSeq = frame.seq;
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
  ///
  /// No key, no signature (phase 044): the connection already proved this
  /// device in its Eidolon check, before the server could greet at all.
  ///
  /// Bound to the [connection] that greeted. Every await below can outlive
  /// that connection - a network change, a Tor circuit that drops, a restart -
  /// and from then on the greeting has nothing left to say: it is dropped
  /// without a word. Its failure branches would otherwise tear down and retry
  /// a connection that is not theirs.
  Future<void> _greet({required SocketConnection connection, required int epoch}) async {
    bool stale() => epoch != _connectionEpoch || !identical(_connection, connection);
    try {
      final since = await _syncRepository.getCursor();
      // Never greeted (or wiped since) - not "at 0". A first greeting that
      // found an empty journal stores 0, and the next one must still ask for
      // what happened in between: read as "first" again, it adopted the head
      // and the messages that had arrived meanwhile never came.
      final firstEver = !await _syncRepository.hasCursor();
      if (stale()) return;
      final provider = _credentialsProvider;
      final credentials = provider == null ? const GreetingCredentials() : await provider();
      if (stale()) return;
      if (credentials == null) {
        // The provider could not tell who we are - a transient storage failure.
        // Greeting anyway could greet for a session that is not there; wait
        // and re-read instead.
        await _teardown(SessionPhase.disconnected);
        _scheduleRetry();
        return;
      }
      if (credentials.unpaired) {
        // Held open, NOT torn down: this is the window `pair` runs in, and it
        // is the one command allowed before a greeting. Nothing else can be
        // sent - every other command waits on the greeting that will not come
        // until pairing has happened. A greeting now would be refused as
        // `unauthenticated`: the server does not know this device's key yet.
        logRepository.debug(target: this, message: 'socket: not paired yet, holding the connection open for pairing');
        return;
      }
      final reply = await _sendOnce(isGreeting: true, via: connection, 'session.hello', <String, dynamic>{
        'schema': 1,
        if (!firstEver) 'since': since,
        // Stated only after a rename: a greeting that repeats a cached name
        // would push it back over a rename made from another device.
        'label': ?credentials.label,
      });
      if (stale()) return;
      if (!reply.ok) {
        logRepository.debug(target: this, message: 'socket: greeting refused: code=${reply.errorCode}');
        // A version mismatch or a malformed greeting is a programmer error, not
        // a blip: the contract marks both non-repeatable (§2.1). Retrying would
        // spin forever against a server that will never accept us.
        if (reply.errorCode == 'unauthenticated') {
          // The server does not know the key this connection proved: revoked,
          // or a server whose store was rebuilt. The device cannot tell those
          // apart and must not: both mean "this is not my server any more".
          // The ONE answer during a session that ends in a forced logout
          // (FR-013) - a channel that would not open never does. Retrying
          // would spin forever against a peer that will keep refusing, so the
          // session is torn down and the app is told.
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
      if (stale()) return;
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
        if (stale()) return;
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
      );
      greetingGeneration++;
      // Read before the limits and kept with them: what the server says about
      // where it can be found belongs to this connection, and its presence is
      // the support flag for everything phase 039 added to the wire (§2.1).
      addresses = ServerAddressesParser.parse(data['addresses']);
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
      final dialled = _dialled;
      if (dialled != null) {
        try {
          _targets?.reportGreeted(dialled);
        } on Object catch (e, st) {
          logRepository.error(target: this, error: 'greeting report failed: ${e.runtimeType}', stackTrace: st);
        }
      }
      _phase.add(SessionPhase.catchingUp);
      logRepository.debug(target: this, message: 'socket: greeted: first=$firstEver cursor=$_helloCursor');
      if (firstEver) {
        // No replay was requested, so the reply's cursor becomes our starting
        // point and the bootstrap happens through ordinary list reads (§3).
        await _syncRepository.advanceCursor(_helloCursor);
        if (stale()) return;
        _phase.add(SessionPhase.live);
      } else if (since >= _helloCursor || _seenSeq >= _helloCursor) {
        // Already level with the server, or the replay overtook this very
        // continuation: either way the catch-up rule has been met.
        _phase.add(SessionPhase.live);
      }
    } on SocketUnavailableException {
      // The connection went away under the greeting - its own drop already
      // tore it down and scheduled what comes next.
      if (stale()) return;
      await _teardown(SessionPhase.disconnected);
      _scheduleRetry();
    } on Object catch (e, st) {
      if (stale()) return;
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
    // A terminal phase is not a drop to recover from. Both terminal values are
    // reached by a teardown that then closes the socket, so `onDone` arrives
    // right behind them - and without this guard it restarted the very ladder
    // those phases exist to stop. Latent for `unsupported` since it was
    // introduced; reachable in practice as of the refused server key, which
    // is triggered by a live network rather than by a rare protocol mismatch.
    if (_phase.value.isTerminal) return;
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
      // Bounded: a peer that never answers the close must not hold the reset -
      // and with it a reconnect or a logout - for as long as it likes.
      await _connection?.close().timeout(_closeBound);
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
    addresses = null;
    _dialled = null;
    _seenSeq = 0;
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
    await _opened.close();
  }
}

/// What a greeting states (contract §3). Who is greeting is not among it any
/// more (phase 044): the connection proved the device's key before the
/// greeting, and the server knows the device by that.
class GreetingCredentials {
  const GreetingCredentials({this.label}) : unpaired = false;

  /// This install has not paired yet, so there is nothing to greet as.
  ///
  /// The connection is still needed - `pair` is the one command allowed before
  /// a greeting - so the socket stays open and simply does not greet. Greeting
  /// anyway would be refused, and the refusal reads as a revocation.
  const GreetingCredentials.unpaired() : label = null, unpaired = true;

  /// Present only on the greeting that follows a rename.
  final String? label;

  /// See [GreetingCredentials.unpaired].
  final bool unpaired;
}
