import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/sync/attachment_prefetch_service.dart';
import 'package:nox_app/data/sync/sync_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/data/remote/api_client.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';

/// Owns the order in which the live channel comes up, which is load-bearing:
///
/// 1. decide which WORLD the cached data belongs to and wipe it if it changed —
///    before anything reads or writes, or a mock-era cursor would reach the
///    greeting and ask a server for history from the future;
/// 2. subscribe the applier — before the socket connects, or the replay that
///    follows the greeting arrives with nobody listening;
/// 3. only then open the socket.
///
/// Deliberately NOT done in a DI constructor: construction order is not a
/// lifecycle, and a socket opened there would outlive logout.
@LazySingleton(env: [Environment.dev])
class LiveSessionStarter {
  LiveSessionStarter(
    this._socket,
    this._syncService,
    this._syncRepository,
    this._config,
    this._session,
    this._chats,
    this._messages,
    this._outbox,
    this._files,
  );

  final NoxSocketClient _socket;
  final SyncService _syncService;
  final SyncRepository _syncRepository;
  final AppConfigRepository _config;
  final SessionRepository _session;
  final ChatRepository _chats;
  final MessageRepository _messages;
  final OutboxRepository _outbox;
  final FileRepository _files;

  StreamSubscription<SessionPhase>? _phaseSub;

  /// Brings the channel up. A build with no configured address stays on the
  /// cached data and never opens a socket.
  /// Waits out a transient storage failure before trying to start again.
  Timer? _retry;

  Future<void> start() async {
    // The address comes from the PAIRING LINK, not from the build. A
    // compile-time address would mean pairing with the server a person
    // presented and then sending their messages somewhere else entirely -
    // which is the opposite of "your own server".
    final paired = await _session.serverAddress();
    if (!paired.hasData) {
      // A read failure is not "this install never paired". Falling back to the
      // build-time address would point a paired device at a different server,
      // whose journal id differs - and the world-change wipe would then throw
      // away everything this person has.
      // Deferred, not abandoned: without a retry a single transient keychain
      // failure would leave the app offline until it is restarted.
      logRepository.debug(target: this, message: 'sync: server address unreadable, retrying');
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 2), () => unawaited(start()));
      return;
    }
    final apiUrl = paired.data ?? _config.config.apiUrl;
    if (apiUrl == null || apiUrl.isEmpty) return;
    // Keyed on the address actually in use: two different servers reachable at
    // one configured address would otherwise look like one world, and the
    // device would carry rows with foreign seqs into the new one.
    await _wipeIfWorldChanged('live:$apiUrl');
    // File bytes travel over REST, and they have to reach the SAME machine the
    // socket does: an attachment uploaded to the build-time address would be
    // referenced from a message on the paired server, where its id means
    // nothing.
    if (getIt.isRegistered<ApiClient>()) getIt<ApiClient>().initBase(address: apiUrl);
    _syncService.start();
    // The greeting is where the server states the payload limits and who we
    // are; both are authoritative and arrive again on every reconnect.
    _phaseSub ??= _socket.phase.listen((phase) {
      if (phase == SessionPhase.catchingUp || phase == SessionPhase.live) unawaited(_adoptGreeting());
    });
    _socket.onUnauthenticated = () => unawaited(_deviceRejected());
    await _socket.start(url: _socketUrl(apiUrl), credentialsProvider: _credentials, onJournalChanged: () => unawaited(_worldChanged()));
  }

  /// Brings the channel back after a sign-in. Logout stops it, and without
  /// this a re-login in the same process would leave the device permanently
  /// disconnected until the app is restarted.
  Future<void> restart() async {
    await stop();
    await start();
  }

  /// Tears the channel down. Called before the logout wipe so live events
  /// cannot repopulate the stores it is in the middle of emptying.
  Future<void> stop() async {
    _retry?.cancel();
    _retry = null;
    await _phaseSub?.cancel();
    _phaseSub = null;
    await _socket.stop();
    await _syncService.stop();
  }

  /// What this connection states about who is greeting (contract §3).
  ///
  /// Read fresh at every greeting, not captured once: a sign-in or a logout in
  /// the same process must greet as the right person. The label is stated only
  /// when this device has just renamed — repeating a cached name on every
  /// greeting would push it back over a rename made from another device.
  Future<GreetingCredentials?> _credentials() async {
    final session = await _session.readSession();
    if (!session.hasData) {
      // Null means "cannot greet yet", NOT "greet as nobody". Stating nothing
      // is an anonymous greeting on the wire, and the server answers that with
      // a throw-away identity: the outgoing queue would then drain under a
      // person who does not exist, and the greeting would hand this session a
      // stranger's author id. A delayed connection is strictly better.
      logRepository.debug(target: this, message: 'sync: session unreadable, greeting deferred');
      return null;
    }
    final data = session.data;
    // Nobody has paired yet. There is no anonymous greeting any more - the
    // server refuses one - so the connection is held open for `pair` and says
    // nothing. This is the state a fresh install sits in, and the state
    // sign-in runs its pairing in.
    if (data == null) return const GreetingCredentials.unpaired();

    final seed = await _session.deviceSecret();
    if (!seed.hasData) {
      // A paired install whose key cannot be read right now. Greeting without
      // it would be refused, and a refusal is indistinguishable from a
      // revocation - which would wipe this device over a transient keychain
      // failure. Defer instead.
      logRepository.debug(target: this, message: 'sync: device key unreadable, greeting deferred');
      return null;
    }
    // No label here any more. It used to ride the greeting behind a "renamed"
    // flag, because a greeting was the only place a name could travel; with
    // identity.setLabel it has its own command, and repeating a cached name on
    // every reconnect is how two devices of one person flip-flop.
    return GreetingCredentials(deviceSeed: seed.data);
  }

  /// The server does not know this device any more: revoked from elsewhere, or
  /// pointed at a store that was rebuilt from nothing.
  ///
  /// Both are the same event from here, and both mean the local data is no
  /// longer this person's on this server. A forced logout is exactly the right
  /// shape: it wipes and puts the app back on the pairing screen.
  Future<void> _deviceRejected() async {
    // Only an install that HAS a session can be revoked. A refusal for a device
    // that never paired is not a revocation - it is the ordinary answer to a
    // greeting that should not have gone out - and wiping on it would delete
    // the very key and address a sign-in in progress just wrote.
    final session = await _session.readSession();
    if (!session.hasData || session.data == null) {
      logRepository.debug(target: this, message: 'sync: refused while unpaired, nothing to clear');
      await stop();
      return;
    }
    logRepository.debug(target: this, message: 'sync: this device is no longer paired, clearing');
    await stop();
    await authRepository.logout(forced: true);
  }

  /// The server's store is not the one this device cached. Everything local
  /// describes a world that no longer exists, so it goes — including the author
  /// id, which would otherwise mark strangers' messages as this user's own.
  Future<void> _worldChanged() async {
    logRepository.debug(target: this, message: 'sync: server store changed, resetting the local world');
    await stop();
    try {
      await _wipeWorld();
      await _session.forgetAuthorId();
      // Nothing to re-assert any more. A rebuilt store has no devices table
      // either, so this device's key is unknown there and the next greeting is
      // refused - the person pairs again, and pairing is what names them.
    } on Object catch (e, s) {
      logRepository.error(target: this, error: e, stackTrace: s);
    } finally {
      // The channel comes back whichever way the wipe ended. This runs
      // detached from the socket's own error handling, so a throw here would
      // otherwise leave the device disconnected until the app restarts.
      await start();
    }
  }

  /// Takes what the greeting declared. Limits feed the composer's pre-flight
  /// check (§3 requires checking BEFORE sending, not learning from a rejection),
  /// and the label is the server's to decide — it may have been changed from
  /// another device while this one was offline.
  Future<void> _adoptGreeting() async {
    final limits = _socket.limits;
    if (limits != null) _config.updateLimits(limits);
    final identity = _socket.identity;
    if (identity == null || identity.id.isEmpty) return;
    // A connection made before anyone signed in was served a one-off identity.
    // Persisting it would hand the next person to sign in a stranger's author
    // id and a stranger's name, and every message they had sent would come back
    // looking like someone else's.
    final session = await _session.readSession();
    if (!session.hasData || session.data == null) return;
    // BOTH halves matter. The label is what the user sees; the author id is what
    // the server stamps on every message, so own-vs-other detection is wrong
    // without it — every message the user sent would come back looking like
    // someone else's.
    await _session.adoptServerIdentity(authorId: identity.id, label: identity.label);
    // The onboarding rescue that used to live here is gone. The greeting no
    // longer carries `created` - the outcome moved to the pair reply (§3),
    // where the decision is actually taken - so this could never fire again,
    // and code that reads as if it still works is worse than none.
  }

  /// The cached rows and the cursor describe ONE world. Mock seqs are minted
  /// from the clock and a server counts from 1, so carrying either across is
  /// worse than starting clean: the cursor would ask for the future and the
  /// rows would mix two id spaces.
  Future<void> _wipeIfWorldChanged(String epoch) async {
    if (await _syncRepository.getEpoch() == epoch) return;
    logRepository.debug(target: this, message: 'sync: data source changed, dropping the local cache once');
    await _wipeWorld();
    await _syncRepository.setEpoch(epoch);
  }

  /// Empties everything that describes one server's world. Shared by the
  /// address-changed path and the journal-changed path, because the two differ
  /// only in how the change was noticed.
  Future<void> _wipeWorld() async {
    // The cursor and the read marks go FIRST, because their survival is the
    // only unrecoverable outcome here. A cursor left above an emptied journal
    // makes the device deaf; a mark left above a rebuilt seq space silently
    // kills every badge, and unlike a stale counter — which the next open
    // resets — nothing ever repairs it. Everything below is merely dirty.
    await _syncRepository.clear();
    await _chats.clearReadMarks();
    // The outgoing queue goes with the cache, and for a sharper reason than the
    // rest of it: a message written against the mock world — or against another
    // server — would otherwise be sent to THIS one on the first drain, landing
    // someone's unrelated text in a chat that has nothing to do with it. The
    // chat id it names does not exist here either, so the send would fail; the
    // text travelling at all is the part that must not happen. Best-effort, so
    // a failure here cannot cost the two clears above.
    try {
      await _outbox.clean();
    } on Object catch (e, s) {
      logRepository.error(target: this, error: e, stackTrace: s);
    }
    // Downloaded bytes belong to the world they came from. Best-effort for the
    // same reason logout treats it that way: a cache directory that will not
    // clear is not worth keeping the app off the screen for.
    try {
      await _files.clean();
    } on Object catch (e, s) {
      logRepository.error(target: this, error: e, stackTrace: s);
    }
    // Prefetch memoises what it has already fetched; those ids belong to the
    // world being discarded. Reached the way logout reaches it.
    if (getIt.isRegistered<AttachmentPrefetchService>()) getIt<AttachmentPrefetchService>().reset();
    await _chats.clean();
    await _messages.clean();
  }

  /// `http(s)` addresses the REST half (blob bytes, phase 028); the socket is
  /// the same host and port with the matching scheme and the `/ws` path.
  /// Accepts both shapes an address can arrive in: a full URL from the build
  /// config, and a bare `host:port` from a pairing link.
  static Uri _socketUrl(String apiUrl) {
    if (!apiUrl.contains('://')) return Uri.parse('ws://$apiUrl/ws');
    final base = Uri.parse(apiUrl);
    return base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/ws');
  }
}
