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
  Future<GreetingCredentials> Function()? _credentialsProvider;

  /// Raised when the server turns out to be a different world than the one this
  /// device cached. The socket only reports it: emptying the local world belongs
  /// to whoever owns it, and a failure there must never cost the reconnect.
  void Function()? _onJournalChanged;

  /// The store identity from the last greeting (contract §3).
  String? journalId;

  /// Last greeting's identity and limits — the server is the authority on both.
  ServerIdentity? identity;
  ServerLimits? limits;

  Stream<SessionPhase> get phase => _phase.stream;
  SessionPhase get currentPhase => _phase.value;
  Stream<ServerEvent> get events => _events.stream;

  /// Opens the connection and keeps it open until [stop]. Safe to call twice.
  Future<void> start({
    required Uri url,
    Future<GreetingCredentials> Function()? credentialsProvider,
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
      _frames = connection.frames.listen(
        _onRawFrame,
        onError: (Object e) => _onDropped('stream error: ${e.runtimeType}'),
        onDone: () => _onDropped('closed by peer'),
        cancelOnError: false,
      );
    } catch (e) {
      _onDropped('connect failed: ${e.runtimeType}');
    }
  }

  void _onRawFrame(dynamic raw) {
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
      final credentials = await _credentialsProvider?.call() ?? const GreetingCredentials();
      final reply = await _sendOnce(isGreeting: true, 'session.hello', <String, dynamic>{
        'schema': 1,
        if (!firstEver) 'since': since,
        // Stated only after a rename: a greeting that repeats a cached name
        // would push it back over a rename made from another device.
        'label': ?credentials.label,
        'login_ref': ?credentials.loginRef,
        'device_key': ?credentials.deviceKey,
      });
      if (!reply.ok) {
        logRepository.debug(target: this, message: 'socket: greeting refused: code=${reply.errorCode}');
        // A version mismatch or a malformed greeting is a programmer error, not
        // a blip: the contract marks both non-repeatable (§2.1). Retrying would
        // spin forever against a server that will never accept us.
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
      if (serverJournal != null && journalId != null && serverJournal != journalId) {
        logRepository.debug(target: this, message: 'socket: server journal changed, local world is stale');
        journalId = null;
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
      journalId = serverJournal ?? journalId;

      _helloCursor = data['cursor'] as int? ?? 0;
      final id = data['identity'];
      if (id is Map<String, dynamic>) {
        identity = ServerIdentity(id: id['id'] as String? ?? '', label: id['label'] as String? ?? '');
      }
      final lim = data['limits'];
      if (lim is Map<String, dynamic>) {
        limits = ServerLimits(
          maxMessageBytes: lim['max_message_bytes'] as int? ?? ServerLimits.contractDefaults.maxMessageBytes,
          maxAttachmentBytes: lim['max_attachment_bytes'] as int? ?? ServerLimits.contractDefaults.maxAttachmentBytes,
          maxFrameBytes: lim['max_frame_bytes'] as int? ?? ServerLimits.contractDefaults.maxFrameBytes,
        );
      }
      // The ladder resets HERE — a greeting is the first proof the peer is real.
      _backoff = _minBackoff;
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
    }
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

  Future<void> _teardown(SessionPhase next) async {
    await _frames?.cancel();
    _frames = null;
    await _connection?.close();
    _connection = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(const SocketUnavailableException('connection lost'));
    }
    _pending.clear();
    // Callers waiting on the handshake must not hang past the drop.
    if (_greeted?.isCompleted == false) _greeted!.completeError(const SocketUnavailableException('connection lost'));
    _greeted = null;
    if (_phase.value != next) _phase.add(next);
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
  const GreetingCredentials({this.loginRef, this.deviceKey, this.label});

  /// One-way derivation of the login identifier — names the PERSON.
  final String? loginRef;

  /// Opaque per-install id — names the DEVICE.
  final String? deviceKey;

  /// Present only on the greeting that follows a rename.
  final String? label;
}
