import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/sync/attachment_prefetch_service.dart';
import 'package:nox_app/data/sync/sync_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/general/identity/identifier_digest.dart';
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
  Future<void> start() async {
    final apiUrl = _config.config.apiUrl;
    if (apiUrl == null || apiUrl.isEmpty) return;
    await _wipeIfWorldChanged('live:$apiUrl');
    _syncService.start();
    // The greeting is where the server states the payload limits and who we
    // are; both are authoritative and arrive again on every reconnect.
    _phaseSub ??= _socket.phase.listen((phase) {
      if (phase == SessionPhase.catchingUp || phase == SessionPhase.live) unawaited(_adoptGreeting());
    });
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
    // A genuinely absent session is the sanctioned anonymous case: nobody has
    // signed in, so there is nothing to claim.
    if (data == null) return const GreetingCredentials();

    final deviceId = await _session.deviceId();
    final dirty = await _session.isLabelDirty();
    return GreetingCredentials(
      loginRef: IdentifierDigest.loginRef(data.identifier),
      deviceKey: deviceId.data,
      label: (dirty.data ?? false) ? data.label : null,
    );
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
      // The new world has never heard this name. Without re-asserting it the
      // greeting states nothing, the server mints User<random>, and the person
      // is silently renamed out of the name they chose.
      await _session.markLabelDirty();
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
    // A person the server already knows has nothing left to onboard. This is
    // the only path that can rescue a device left sitting on the naming screen
    // while the same person named themselves elsewhere - and it advances the
    // flag only, so a reconnect before naming cannot skip the step.
    final created = identity.created;
    if (created != null) {
      final advanced = await _session.advanceOnboardingIfKnown(created: created);
      // Re-derive only when the flag actually moved: the navigation spine
      // swaps the root route off the naming screen from this.
      if (advanced.data ?? false) await appStateRepository.fetchAppState();
    }
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
    // The outgoing queue goes with the cache, and for a sharper reason than the
    // rest of it: a message written against the mock world — or against another
    // server — would otherwise be sent to THIS one on the first drain, landing
    // someone's unrelated text in a chat that has nothing to do with it. The
    // chat id it names does not exist here either, so the send would fail; the
    // text travelling at all is the part that must not happen.
    await _outbox.clean();
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
    await _syncRepository.clear();
    await _chats.clean();
    await _messages.clean();
  }

  /// `http(s)` addresses the REST half (blob bytes, phase 028); the socket is
  /// the same host and port with the matching scheme and the `/ws` path.
  static Uri _socketUrl(String apiUrl) {
    final base = Uri.parse(apiUrl);
    return base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/ws');
  }
}
