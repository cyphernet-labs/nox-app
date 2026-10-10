import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/channel/channel_http_client.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/sync/attachment_prefetch_service.dart';
import 'package:nox_app/domain/service/attachment_download_service.dart';
import 'package:nox_app/data/sync/connection/connection_path_selector.dart';
import 'package:nox_app/data/sync/sync_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/data/remote/api_client.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
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
    this._channels,
    this._selector,
    this._addresses,
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
  final ChannelHttpClient _channels;
  final ConnectionPathSelector _selector;
  final ServerAddressesRepository _addresses;

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
      _retryLater();
      return;
    }
    final apiUrl = paired.data;
    // No build-time fallback. `AppConfig.apiUrl` names a machine nobody ever
    // presented, so there is no key a connection to it could be checked
    // against. An install that has not paired simply does not connect.
    if (apiUrl == null || apiUrl.isEmpty) return;

    final storedKey = await _session.serverKey();
    if (!storedKey.hasData) {
      // Treated like an unreadable address, and for the same reason: a
      // transient keychain failure is not a statement about which server this
      // is.
      logRepository.debug(target: this, message: 'sync: server key unreadable, retrying');
      _retryLater();
      return;
    }
    final serverKeyText = storedKey.data;
    final serverKey = _keyBytes(serverKeyText);
    if (serverKeyText == null || serverKey == null) {
      // An address with nothing to check it against: a session paired before
      // phase 044, which bootstrap retires (FR-025). Connecting anyway would
      // accept whatever answered; the way out is to pair again, not to trust
      // harder.
      logRepository.debug(target: this, message: 'sync: paired address has no server key, refusing to connect');
      return;
    }
    final seed = await _session.deviceSecret();
    final deviceSeed = seed.hasData ? _keyBytes(seed.data) : null;
    if (deviceSeed == null) {
      // The key this device proves itself with cannot be read right now - a
      // keychain still locked after a reboot. A failed attempt, never a wipe:
      // without the key there is simply nothing to connect with yet.
      logRepository.debug(target: this, message: 'sync: device key unreadable, retrying');
      _retryLater();
      return;
    }
    // Bound on every start, never captured at construction: the client is a
    // singleton that outlives pairing, re-pairing and logout.
    _channels.bind(serverKey: serverKey, deviceSeed: deviceSeed);

    // Keyed on the SERVER, by its key (phase 040, FR-011; phase 044). An
    // address is a place: the server moves between them, and the same one
    // leads to somebody else's machine on another network. The key is what
    // every connection proves, so two worlds cannot share one.
    await _wipeIfWorldChanged(serverKeyText);
    // File bytes travel over REST, and they have to reach the SAME machine the
    // socket does, over the same checked client: an attachment uploaded
    // anywhere else would be referenced from a message on the paired server,
    // where its id means nothing. The link's address until a path is chosen;
    // every greeting then points it at the path in use (FR-009).
    if (getIt.isRegistered<ApiClient>()) getIt<ApiClient>().initBase(address: _restUrl(apiUrl));
    _syncService.start();
    // The greeting is where the server states the payload limits and who we
    // are; both are authoritative and arrive again on every reconnect.
    _phaseSub ??= _socket.phase.listen((phase) {
      if (phase == SessionPhase.catchingUp || phase == SessionPhase.live) unawaited(_adoptGreeting());
    });
    _socket.onUnauthenticated = () => unawaited(_deviceRejected());
    // Asked before every attempt: direct first, then Tor (phase 040). Its
    // probes open channels too, under the same two keys.
    _selector.begin(linkAddress: _hostPort(apiUrl), serverKey: serverKey, deviceSeed: deviceSeed);
    deviceSeed.fillRange(0, deviceSeed.length, 0);
    await _socket.start(targets: _selector, credentialsProvider: _credentials, onJournalChanged: () => unawaited(_worldChanged()));
  }

  /// Brings the channel back after a sign-in. Logout stops it, and without
  /// this a re-login in the same process would leave the device permanently
  /// disconnected until the app is restarted.
  ///
  /// The Tor client is left running across it while it is healthy: a restart
  /// is a sign-in's re-greeting, the way back from a refusal, or Try again on
  /// No connection (phase 042), and the next round would only bring a working
  /// client up again from its directories. One that failed or is stuck coming
  /// up is stopped by the selector instead.
  ///
  /// A restart asked for while one is under way joins it. Nothing else orders
  /// a stop against a start here, and two presses of Try again would otherwise
  /// interleave one restart's stop with the other's start.
  Future<void> restart() => _restarting ??= _restartOnce().whenComplete(() => _restarting = null);

  Future<void>? _restarting;

  Future<void> _restartOnce() async {
    await _stop(keepTor: true);
    await start();
  }

  /// Tears the channel down. Called before the logout wipe so live events
  /// cannot repopulate the stores it is in the middle of emptying.
  Future<void> stop() => _stop(keepTor: false);

  Future<void> _stop({required bool keepTor}) async {
    _retry?.cancel();
    _retry = null;
    await _phaseSub?.cancel();
    _phaseSub = null;
    await _socket.stop();
    await _syncService.stop();
    // After the socket, so no new round starts; Tor stops here on a logout.
    await _selector.end(keepTor: keepTor);
    // Forget the server. A logout leaves nothing this install is entitled to
    // talk to, and keys left bound would let a connection still being torn
    // down keep reaching it.
    _channels.unbind();
  }

  /// Waits out a transient storage failure. Without it a single unreadable
  /// keychain read would leave the app offline until it is restarted.
  void _retryLater() {
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 2), () => unawaited(start()));
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

    // Nobody is named here: the connection proved this device's key before
    // the server greeted (phase 044). And no label: it used to ride the
    // greeting behind a "renamed" flag, because a greeting was the only place
    // a name could travel; with identity.setLabel it has its own command, and
    // repeating a cached name on every reconnect is how two devices of one
    // person flip-flop.
    return const GreetingCredentials();
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
    // Attachment bytes follow the path the socket took: the same machine, by
    // the same way, under the same check (FR-009).
    final url = _socket.currentUrl;
    if (url != null && getIt.isRegistered<ApiClient>()) getIt<ApiClient>().initBase(address: _restUrlOf(url));
    // Where the server can be found, as it says itself (FR-010). Stored before
    // anything that can return early below: an install that has not finished
    // signing in needs the onion address as much as one that has.
    final stated = _socket.addresses;
    if (stated != null) await _addresses.saveFromServer(direct: stated.direct, public: stated.public, onion: stated.onion);
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
  ///
  /// The world is named by the server's key (`key:<base64>`, phase 044). Any
  /// other name - an address (`live:`) or a certificate fingerprint (`fp:`)
  /// from before - belongs to a server this install no longer has a session
  /// with: nothing is migrated (FR-025).
  Future<void> _wipeIfWorldChanged(String serverKey) async {
    final epoch = 'key:$serverKey';
    final stored = await _syncRepository.getEpoch();
    if (stored == epoch) return;
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
    // Prefetch memoises what it has already fetched; those ids belong to the
    // world being discarded. Reached the way logout reaches it, and before the
    // downloads stop, so its worker does not start the old world's next
    // picture into the wipe (phase 043).
    if (getIt.isRegistered<AttachmentPrefetchService>()) getIt<AttachmentPrefetchService>().reset();
    // Downloads of the old world stop first (phase 043), or one would write
    // its next chunk into the cache being emptied. On its own, so that a stop
    // that fails still lets the cache go.
    try {
      if (getIt.isRegistered<AttachmentDownloadService>()) await getIt<AttachmentDownloadService>().reset();
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
    await _chats.clean();
    await _messages.clean();
  }

  /// The stored address as a bare `host:port`, whatever shape it arrived in.
  ///
  /// The path selector dials `wss://<host:port>/ws` and nothing else - there is
  /// no plain fallback and no way to ask for one. A channel that can be talked
  /// down to cleartext is a channel somebody talks down.
  static String _hostPort(String apiUrl) {
    if (!apiUrl.contains('://')) return apiUrl;
    final uri = Uri.parse(apiUrl);
    return uri.hasPort ? '${uri.host.contains(':') ? '[${uri.host}]' : uri.host}:${uri.port}' : uri.host;
  }

  /// The REST base for attachment bytes: the same machine, `https`.
  static String _restUrl(String apiUrl) {
    if (!apiUrl.contains('://')) return 'https://$apiUrl';
    return Uri.parse(apiUrl).replace(scheme: 'https').toString();
  }

  /// The REST base for the machine a socket URL names.
  static String _restUrlOf(Uri socketUrl) =>
      Uri(scheme: 'https', host: socketUrl.host, port: socketUrl.hasPort ? socketUrl.port : null).toString();

  /// A stored key as its 32 bytes; null for anything else - absent, not
  /// base64, the wrong length. Never a reason to throw: a value that cannot
  /// be a key is no key.
  static Uint8List? _keyBytes(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final bytes = base64.decode(text);
      return bytes.length == 32 ? bytes : null;
    } on FormatException {
      return null;
    }
  }
}
