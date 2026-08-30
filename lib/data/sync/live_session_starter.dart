import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:nox_app/data/remote/socket/nox_socket_client.dart';
import 'package:nox_app/data/sync/sync_service.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app_config/app_config_repository.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
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
  LiveSessionStarter(this._socket, this._syncService, this._syncRepository, this._config, this._session, this._chats, this._messages);

  final NoxSocketClient _socket;
  final SyncService _syncService;
  final SyncRepository _syncRepository;
  final AppConfigRepository _config;
  final SessionRepository _session;
  final ChatRepository _chats;
  final MessageRepository _messages;

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
    await _socket.start(
      url: _socketUrl(apiUrl),
      // Read at every greeting: a reconnect that forgot the name would be given
      // a fresh server-minted one, renaming the user behind their back.
      labelProvider: () async => (await _session.readSession()).data?.label,
    );
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

  /// Takes what the greeting declared. Limits feed the composer's pre-flight
  /// check (§3 requires checking BEFORE sending, not learning from a rejection),
  /// and the label is the server's to decide — it may have been changed from
  /// another device while this one was offline.
  Future<void> _adoptGreeting() async {
    final limits = _socket.limits;
    if (limits != null) _config.updateLimits(limits);
    final identity = _socket.identity;
    if (identity == null || identity.id.isEmpty) return;
    // BOTH halves matter. The label is what the user sees; the author id is what
    // the server stamps on every message, so own-vs-other detection is wrong
    // without it — every message the user sent would come back looking like
    // someone else's.
    await _session.adoptServerIdentity(authorId: identity.id, label: identity.label);
  }

  /// The cached rows and the cursor describe ONE world. Mock seqs are minted
  /// from the clock and a server counts from 1, so carrying either across is
  /// worse than starting clean: the cursor would ask for the future and the
  /// rows would mix two id spaces.
  Future<void> _wipeIfWorldChanged(String epoch) async {
    if (await _syncRepository.getEpoch() == epoch) return;
    logRepository.debug(target: this, message: 'sync: data source changed, dropping the local cache once');
    await _syncRepository.clear();
    await _chats.clean();
    await _messages.clean();
    await _syncRepository.setEpoch(epoch);
  }

  /// `http(s)` addresses the REST half (blob bytes, phase 028); the socket is
  /// the same host and port with the matching scheme and the `/ws` path.
  static Uri _socketUrl(String apiUrl) {
    final base = Uri.parse(apiUrl);
    return base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/ws');
  }
}
