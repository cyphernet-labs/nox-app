import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';
import 'package:nox_app/data/repository/connection/connection_storage.dart';
import 'package:nox_app/data/sync/attachment_prefetch_service.dart';
import 'package:nox_app/domain/service/attachment_download_service.dart';
import 'package:nox_app/data/sync/live_identity_handshake.dart';
import 'package:nox_app/general/pairing/device_keys.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:nox_app/general/platform_utils.dart';
import 'package:nox_app/data/sync/live_session_starter.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/base_repository_exception.dart';
import 'package:nox_app/domain/exception/pairing_exception.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/app/app_state_type.dart';
import 'package:nox_app/domain/model/connection/connection_settings.dart';
import 'package:nox_app/domain/model/session/pair_refusal.dart';
import 'package:nox_app/domain/model/session/pending_pairing.dart';
import 'package:nox_app/domain/model/session/session_phase.dart';
import 'package:nox_app/domain/repository/app/app_state_repository.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/device/device_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/connection/server_addresses_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';
import 'package:nox_app/domain/service/session_phase_service.dart';
import 'package:nox_app/domain/service/tor_service.dart';

/// Mutate source-of-truth (session) → re-derive app state. Single logout path;
/// only forced logout passes `sessionExpired`. Sign-in is a stub (backend TBD).
@LazySingleton(as: AuthRepository, env: [Environment.dev, Environment.prod, Environment.test])
class AuthRepositoryImpl with BaseRepositoryHelper implements AuthRepository {
  AuthRepositoryImpl(
    this._sessionRepository,
    this._appStateRepository,
    this._chatRepository,
    this._messageRepository,
    this._syncRepository,
    this._outboxRepository,
    this._fileRepository,
  );

  final SessionRepository _sessionRepository;
  final AppStateRepository _appStateRepository;
  final ChatRepository _chatRepository;
  final MessageRepository _messageRepository;
  final SyncRepository _syncRepository;
  final OutboxRepository _outboxRepository;
  final FileRepository _fileRepository;

  /// Whether a sign-in waits for approval on another device (phase 046).
  final BehaviorSubject<bool> _awaitingApproval = BehaviorSubject<bool>.seeded(false);

  @override
  Stream<bool> watchAwaitingApproval() => _awaitingApproval.stream;

  @override
  Future<void> cancelPairing() async => liveIdentityHandshake?.cancelPairing();

  @override
  Future<RepositoryResult<PendingPairing?>> pendingPairing() {
    return execute<PendingPairing?>(() async {
      final stored = await _sessionRepository.readPendingPairing();
      // A keychain that cannot be read right now resumes nothing - and undoes
      // nothing either.
      if (!stored.hasData) return RepositoryResult<PendingPairing?>.error(exception: stored.exception!);
      final pending = stored.data;
      if (pending == null) return const RepositoryResult<PendingPairing?>.success(data: null);
      if (!DateTime.now().isBefore(pending.waitUntil)) {
        // Its time ran out while the app was closed. Undone like any sign-in
        // that did not land: the channel it brought up at launch towards the
        // server it named stops, and the server's key and addresses go.
        logRepository.debug(target: this, message: 'sign-in: the wait for approval ran out while the app was closed');
        await _rollBackSignIn();
        return const RepositoryResult<PendingPairing?>.success(data: null);
      }
      return RepositoryResult<PendingPairing?>.success(data: pending);
    });
  }

  /// Signs in by presenting a pairing link, and lets the SERVER decide whether
  /// onboarding is due.
  ///
  /// The order is the whole point. Parse the link, remember which server it
  /// names - its key and its addresses - mint this device's key, pair, take
  /// the outcome from the answer, and only then move the navigation.
  /// Remembering the server FIRST is what makes the connection go to the
  /// machine the person actually presented, and what every connection's
  /// check is made against: the channel opens only once the machine answering
  /// has proved the link's key, and only then does the token go out.
  ///
  /// The refusals stay apart because the person's next action differs: a link
  /// that will not parse means "scan it again", a link from a newer server
  /// means "update the app", an expired token means "issue a new invite", a
  /// rejected one means "this is not usable". A failed attempt rolls the
  /// session back, because a stored identity with no settled outcome would
  /// strand the next launch in onboarding.
  @override
  Future<RepositoryResult<bool>> signIn({required String identifier, ConnectionSettings? connection}) {
    return execute<bool>(() async {
      final PairingLink link;
      try {
        link = PairingLink.parse(identifier);
      } on PairingLinkException catch (e) {
        return RepositoryResult<bool>.error(
          exception: switch (e.error) {
            // A link that will not parse: the person scans or pastes it again.
            PairingLinkError.malformed => RepositoryException.invalidRequest,
            // A link from a server newer than this build: the person updates
            // the app. The same answer a server gives a client too old for it.
            PairingLinkError.newerVersion => RepositoryException.unsupportedSchema,
          },
        );
      }
      // The connection starts at the link's first direct address - the one
      // the connection screen showed - or, for a link with none, at the
      // address the person typed there. Every address the link carries is
      // stored with the server's, and what the person changed on the
      // connection screen with them, so the path selector can try them all:
      // directly first, and through Tor when the person allowed it (phase
      // 045) - the pairing itself included.
      final direct = link.directAddresses;
      final typed = connection?.serverAddress.trim();
      final start = direct.isNotEmpty ? direct.first : typed;
      if (start == null || start.isEmpty) return const RepositoryResult<bool>.error(exception: RepositoryException.connection);
      final saved = await _sessionRepository.saveServer(address: start, serverKey: link.serverKeyBase64);
      if (!saved.hasData) return saved;
      await _storeLinkAddresses(link, direct, connection);

      final handshake = liveIdentityHandshake;
      if (handshake == null) {
        // No live channel in this build (mock flavors). There is no server to
        // ask, so onboarding is due.
        final stored = await _sessionRepository.saveIdentifier(identifier: link.token, onboardingComplete: false);
        if (!stored.hasData) return stored;
        return _finishSignIn(onboardingComplete: false);
      }

      final seed = await _sessionRepository.deviceSecret();
      if (!seed.hasData) {
        // Rolled back like every other exit in this method. saveServer has
        // already run, so returning without it leaves the address and the
        // key of a machine this install has no session with - the next launch
        // dials it, greets as unpaired for ever, and the world epoch is keyed
        // on it.
        await _rollBackSignIn();
        return RepositoryResult<bool>.error(exception: seed.exception!);
      }

      try {
        final greeting = await _pair(handshake, link: link, identifier: identifier, connection: connection);
        if (!greeting.outcomeStated) {
          await _rollBackSignIn();
          return const RepositoryResult<bool>.error(exception: RepositoryException.connection);
        }
        // The identifier slot now holds the token this install paired with: it
        // is what makes readSession() report a session at all, and it is not a
        // secret any more - the key is.
        final stored = await _sessionRepository.saveIdentifier(identifier: link.token, onboardingComplete: false);
        if (!stored.hasData) {
          // Same rollback, and here it also clears the address the failed
          // attempt stored. The pairing itself landed server-side, so the token
          // is spent either way - what must not survive is a device pointed at
          // a machine it has no session with.
          await _rollBackSignIn();
          return stored;
        }
        // The identity comes from the pair reply, not from the fact that THIS
        // device presented a claim link: the server is the only one who knows,
        // and a device that inferred it would be right until the day it was
        // not. Stored now so the name is on screen without waiting for the
        // greeting that follows.
        if (greeting.authorId.isEmpty) {
          // An unreadable `identity.id` degrades to '' upstream, and
          // resolveIdentity treats '' as absent - it then falls back to the
          // login identifier, whose slot since 032 holds the pairing TOKEN. So
          // nothing is stored, and the greeting that follows repairs it.
          logRepository.debug(target: this, message: 'sign-in: the pair reply named nobody, waiting for the greeting');
        } else {
          final adopted = await _sessionRepository.adoptServerIdentity(authorId: greeting.authorId, label: greeting.label);
          if (!adopted.hasData) {
            // NOT fatal, and deliberately not a rollback: the claim token is
            // already spent, so discarding here would leave the device unable
            // to pair again - the brick this path was rewritten to avoid.
            logRepository.debug(target: this, message: 'sign-in: identity not stored yet, the greeting will repair it');
          }
        }
        if (greeting.created!) _sessionRepository.noteOnboardingStartedHere();
        // Re-greet. The connection `pair` ran on was never greeted - its key
        // was nobody's when it opened - so it carries no session; the restart
        // greets on a fresh one as the person just paired. Storing the session
        // first is what makes this greeting state a person.
        try {
          await handshake.greet(within: _greetingAfterPairing);
        } on Object {
          // The pairing itself landed. A greeting that did not is an ordinary
          // reconnect away, and the session is already valid.
        }
        return _finishSignIn(onboardingComplete: !greeting.created!);
      } on PairingFailed {
        // Not about the link. Retryable, and the person is told so rather than
        // sent looking for an invite they already have.
        await _rollBackSignIn();
        return const RepositoryResult<bool>.error(exception: RepositoryException.internal);
      } on PairingCancelled {
        // The person withdrew the request (phase 046). Rolled back like any
        // attempt that did not land; the screen has nothing to explain.
        await _rollBackSignIn();
        return const RepositoryResult<bool>.error(exception: PairingException.cancelled);
      } on PairingRefused catch (e) {
        await _rollBackSignIn();
        // Three refusals, three answers. Each ends in "ask for a new link",
        // and each says why: the link - or the request an invite opened,
        // which lives exactly as long - expired; the link is spent; or the
        // device that issued the invite said no (phase 046).
        final BaseRepositoryException exception = switch (e.reason) {
          PairRefusal.expired => RepositoryException.notFound,
          PairRefusal.notUsable => RepositoryException.authentication,
          PairRefusal.declined => PairingException.declined,
        };
        return RepositoryResult<bool>.error(exception: exception);
      } on Object catch (e, st) {
        // The TYPE only. A FormatException from a base64 decode carries the
        // offending source in its message, which here would be the link or the
        // key seed - and a token in a log is still a usable pairing credential
        // (Principle I, FR-035).
        logRepository.error(target: this, error: e.runtimeType, stackTrace: st);
        await _rollBackSignIn();
        return const RepositoryResult<bool>.error(exception: RepositoryException.connection);
      }
    });
  }

  /// Presents the link, and waits with it when it is an invite whose request
  /// waits for approval (phase 046).
  ///
  /// The wait is remembered while it lasts - the link, what was set on the
  /// connection screen and this device's deadline - so a restart within its
  /// time goes on waiting for the same request (FR-011); the same link
  /// remembered from before keeps its first deadline. Forgotten when the wait
  /// ends, whichever way: a link left in storage is a credential nobody needs.
  Future<IdentityHandshake> _pair(
    LiveIdentityHandshake handshake, {
    required PairingLink link,
    required String identifier,
    ConnectionSettings? connection,
  }) async {
    final remembered = (await _sessionRepository.readPendingPairing()).data;
    final resumeUntil = remembered != null && PairingLink.tryParse(remembered.link)?.token == link.token ? remembered.waitUntil : null;
    Future<void>? remembering;
    try {
      return await handshake.pair(
        link: link,
        platform: PlatformUtils.family,
        waitUntil: resumeUntil,
        onPending: (pending) {
          _awaitingApproval.add(true);
          remembering = _sessionRepository.savePendingPairing(
            PendingPairing(link: identifier, waitUntil: pending.waitUntil, connection: connection),
          );
        },
      );
    } finally {
      _awaitingApproval.add(false);
      // After the write that remembered it, or the record would outlive this.
      await remembering;
      await _sessionRepository.clearPendingPairing();
    }
  }

  /// Undoes a sign-in that did not land: the channel it brought up towards the
  /// server it named stops first, so nothing in flight writes back what
  /// [SessionRepository.discardSignIn] then removes - the server's key, its
  /// address and the addresses the link carried among it.
  Future<void> _rollBackSignIn() async {
    if (getIt.isRegistered<LiveSessionStarter>()) await getIt<LiveSessionStarter>().stop();
    await _sessionRepository.discardSignIn();
  }

  /// How long sign-in waits for the greeting that follows a pairing. At home
  /// it comes in milliseconds, and nothing waits on it past this: the restart
  /// has already happened, and the greeting arrives on its own (phase 040,
  /// T053).
  static const Duration _greetingAfterPairing = Duration(seconds: 2);

  /// Stores every address the link carries - the direct ones in its order,
  /// and the onion address its service key derives - with what the person
  /// set on the connection screen (phase 045): a field changed from the
  /// link's value is a hand edit, a cleared onion field means no onion
  /// address, and `Use Tor` as ticked. The greetings that follow replace the
  /// link's addresses with what the server says about itself. Best effort:
  /// without them the session still starts at the link's first address.
  Future<void> _storeLinkAddresses(PairingLink link, List<String> direct, ConnectionSettings? connection) async {
    if (!getIt.isRegistered<ServerAddressesRepository>()) return;
    final serviceKey = link.onionServiceKey;
    final host = serviceKey == null || !getIt.isRegistered<TorService>() ? null : getIt<TorService>().onionFromPublicKey(serviceKey);
    final linkOnion = host == null ? null : '$host:443';
    String? manualAddress;
    String? manualOnion;
    if (connection != null) {
      final typed = connection.serverAddress.trim();
      // Only an edit of the link's own address: a link without one started
      // the session at what was typed, which is no edit of anything.
      if (direct.isNotEmpty && typed.isNotEmpty && typed != direct.first) manualAddress = typed;
      final typedOnion = connection.onionAddress ?? '';
      if (typedOnion != (linkOnion ?? '')) manualOnion = typedOnion;
    }
    final stored = await getIt<ServerAddressesRepository>().saveFromLink(
      direct: direct,
      onion: linkOnion,
      manualAddress: manualAddress,
      manualOnion: manualOnion,
      useTor: connection?.useTor ?? false,
    );
    if (!stored.hasData) logRepository.debug(target: this, message: 'sign-in: the link addresses were not stored, starting at its first');
  }

  /// Revokes this device's own key before the local wipe, when there is a
  /// channel to say it on. Never blocks the logout: a person who chose to sign
  /// out must sign out.
  ///
  /// "A channel" is a greeted one, now (contract §8A: with a live connection
  /// the revoke goes out before the wipe; without one the wipe is
  /// unconditional). A command sent without one would wait for a connection
  /// that may be minutes away through Tor - the person staring at the logout
  /// for the bound below to buy nothing, since the orphaned key is revoked
  /// from another device either way.
  Future<void> _revokeOwnKey() async {
    final devices = getIt.isRegistered<DeviceRepository>() ? getIt<DeviceRepository>() : null;
    if (devices == null) return;
    final phase = getIt.isRegistered<SessionPhaseService>() ? getIt<SessionPhaseService>().phase : null;
    if (phase != SessionPhase.live && phase != SessionPhase.catchingUp) {
      logRepository.debug(target: this, message: 'logout: not connected, the key is revoked from another device');
      return;
    }
    try {
      final seed = await _sessionRepository.deviceSecret();
      if (!seed.hasData) return;
      await devices.revoke(deviceKey: await DeviceKeys.publicKey(seed.data!));
    } on Object catch (e, st) {
      // The type only: a decode failure would otherwise put the seed in the log.
      logRepository.error(target: this, error: e.runtimeType, stackTrace: st);
    }
  }

  Future<RepositoryResult<bool>> _finishSignIn({required bool onboardingComplete}) async {
    if (onboardingComplete) {
      final marked = await _sessionRepository.setOnboardingComplete();
      if (!marked.hasData) return marked;
    }
    // Logout cancelled the drain's phase subscription. Without re-arming it
    // here, a re-login in the same process would only ever send when the
    // thread asked directly - a message queued offline would sit there through
    // the next reconnect with nobody to notice it.
    if (getIt.isRegistered<OutboxService>()) getIt<OutboxService>().start();

    await _appStateRepository.fetchAppState();
    // The outcome is the state, not the write: a transient storage failure
    // leaves the derivation where it was, and reporting success then would
    // show a sign-in that goes nowhere and says nothing.
    final settled = _appStateRepository.currentState;
    if (settled == AppStateType.unauthorized || settled == AppStateType.init) {
      return const RepositoryResult<bool>.error(exception: RepositoryException.unknown);
    }
    return const RepositoryResult<bool>.success(data: true);
  }

  @override
  Future<RepositoryResult<bool>> completeOnboarding({String? label}) async {
    // The name goes to the server BEFORE it is stored locally. Storing first
    // and telling the server after - or not checking whether it landed - shows
    // a name the next greeting silently replaces with the assigned one, and the
    // person has no way to know their choice was lost.
    var landed = label == null || label.isEmpty;
    if (!landed) {
      final devices = getIt.isRegistered<DeviceRepository>() ? getIt<DeviceRepository>() : null;
      if (devices == null) {
        // No live channel in this build: nothing to tell, so the local name is
        // the whole truth.
        landed = true;
      } else {
        landed = (await devices.setLabel(label: label)).hasData;
      }
    }

    // Onboarding completes either way - a person who chose a name must not be
    // stranded on the naming screen because one command failed - but the name
    // is only kept if the server actually has it. Keeping it locally otherwise
    // would be a lie the next greeting corrects.
    return _deriveAfter(() => _sessionRepository.setOnboardingComplete(label: landed ? label : null));
  }

  /// The logout under way, if one is.
  Future<RepositoryResult<bool>>? _loggingOut;

  /// One logout at a time, and a second one joins the first.
  ///
  /// The case this exists for is a voluntary logout's own echo. It revokes
  /// this device's key first, and the server answers that by telling every
  /// connection of the key - this one included - `device.revoked`, which is
  /// the forced logout's trigger. The guard against acting on it reads the
  /// session, and the wipe that empties it is a few storage calls behind the
  /// revoke's reply: the event can win that race, and a second, forced wipe
  /// then tells the person their session expired when they signed out.
  /// Joined, the forced one IS the voluntary one - same wipe, same outcome,
  /// no expiry notice.
  @override
  Future<RepositoryResult<bool>> logout({bool forced = false}) {
    final running = _loggingOut;
    if (running != null) return running;
    final run = _logout(forced: forced);
    _loggingOut = run;
    return run.whenComplete(() {
      if (identical(_loggingOut, run)) _loggingOut = null;
    });
  }

  Future<RepositoryResult<bool>> _logout({required bool forced}) {
    // Gate the re-derive on a successful wipe: a failed clear() (e.g. a secure-storage
    // PlatformException) must NOT report success while the identifier survives —
    // otherwise the user silently stays authorized (Constitution I: logout fully wipes).
    // After the session is cleared, drop the cached chats + messages so a re-login as a
    // different identity starts clean (Constitution I: full local wipe on identity switch).
    return _deriveAfter(
      () async {
        // A voluntary logout revokes THIS device's own key, so the key stops
        // being a way in rather than merely being forgotten here. Best effort,
        // and only while connected: offline the local wipe is unconditional and
        // the orphaned key is revoked from another device - the accepted price
        // (contract §8A). A forced logout skips it: the server already refused
        // us, and asking it to revoke a key it does not know would be noise.
        // Bounded: a person who chose to sign out must sign out, and the local
        // wipe is what actually protects them. A server that does not answer
        // gets a few seconds, not the full command timeout with the progress
        // dialog already gone - the orphaned key is revoked from another
        // device, which is the accepted price (§8A).
        if (!forced) {
          await _revokeOwnKey().timeout(
            const Duration(seconds: 3),
            onTimeout: () => logRepository.debug(target: this, message: 'logout: revoke did not answer, wiping anyway'),
          );
        }
        return _sessionRepository.clear();
      },
      sessionExpired: forced,
      afterMutate: () async {
        // Close the live channel BEFORE emptying anything: an event applied
        // mid-wipe would repopulate the stores this is in the middle of
        // clearing, leaving a logged-out device holding someone's messages.
        if (getIt.isRegistered<LiveSessionStarter>()) await getIt<LiveSessionStarter>().stop();
        // Swept once more with the channel down. A greeting that landed
        // between the wipe and the stop could have stored the server's
        // addresses again (FR-018). Through their own queue, so a write
        // already under way lands first and is wiped, rather than landing
        // after.
        if (getIt.isRegistered<ServerAddressesRepository>()) await getIt<ServerAddressesRepository>().clear();
        if (getIt.isRegistered<FlutterSecureStorage>()) {
          try {
            await ConnectionStorage.delete(getIt<FlutterSecureStorage>());
          } catch (error, stackTrace) {
            logRepository.error(target: this, error: error.runtimeType, stackTrace: stackTrace);
          }
        }
        // The Tor client's state goes with the session (FR-018, FR-024): its
        // directories hold the guards and descriptors it learned on the way to
        // THIS person's server. Best-effort like the file cache below - a
        // directory that will not delete is no reason to leave the previous
        // identity's chats on disk.
        if (getIt.isRegistered<TorService>()) {
          try {
            await getIt<TorService>().wipe();
          } catch (error, stackTrace) {
            logRepository.error(target: this, error: error.runtimeType, stackTrace: stackTrace);
          }
        }
        // The outgoing drain closes with it, and for the same reason: a pass
        // still in flight would persist a message into the store being emptied.
        //
        // stop() disarms it until the next start(), which is a sign-in. If the
        // wipe below throws, no sign-in follows and the drain would stay dead
        // for the life of the process while the app still shows the user signed
        // in — so a failed wipe puts it back.
        if (getIt.isRegistered<OutboxService>()) await getIt<OutboxService>().stop();
        try {
          // The queue goes FIRST of the stores. It holds message texts that were
          // never sent, and a crash later in the wipe would leave them for the
          // next identity — who would then have them sent, under their name, by
          // the drain that re-arms at the next sign-in.
          await _outboxRepository.clean();
          // The prefetch remembers which files it already tried. That memory
          // belongs to the identity that was signed in: without clearing it,
          // the next person's pictures are never fetched for the life of the
          // process, because their message ids may repeat ours. And it goes
          // BEFORE the downloads stop (phase 043): its worker would otherwise
          // take the next picture of this identity as soon as the current one
          // was stopped, and start it into the wipe.
          if (getIt.isRegistered<AttachmentPrefetchService>()) getIt<AttachmentPrefetchService>().reset();
          // Downloads stop FIRST of the bytes (phase 043): one still running
          // would write its next chunk into the directory being deleted, or
          // rename a finished file into it right after. On its own, so that a
          // stop that fails still lets the cache go.
          try {
            if (getIt.isRegistered<AttachmentDownloadService>()) await getIt<AttachmentDownloadService>().reset();
          } catch (error, stackTrace) {
            logRepository.error(target: this, error: error, stackTrace: stackTrace);
          }
          // Downloaded bytes go with them, and for the same reason: they are
          // other people's pictures, sitting in a cache on a device that has
          // just been handed back to nobody in particular.
          //
          // Guarded, and deliberately: this is the only filesystem delete in
          // the wipe and the one most able to fail — a file still open from an
          // in-flight download is enough on Windows. Letting it throw would
          // abandon the wipe half-done and leave the previous identity's chats,
          // messages and cursor on disk, which is far worse than a cached
          // picture surviving. Best-effort here, loud in the log.
          try {
            await _fileRepository.clean();
          } catch (error, stackTrace) {
            logRepository.error(target: this, error: error, stackTrace: stackTrace);
          }
          // The cursor goes next: a crash mid-wipe must leave it behind the
          // stores (safe - replay re-applies idempotently), never ahead of an
          // emptied store (a stale high `since` would skip every row below it
          // and the monotonic guard would keep it stuck forever).
          // Before the cursor, deliberately. A mark that outlived it would sit
          // above a rebuilt seq space and suppress every badge - and unlike a
          // stale counter, which the next open resets, nothing ever repairs it.
          await _chatRepository.clearReadMarks();
          await _syncRepository.clear();
          await _chatRepository.clean();
          await _messageRepository.clean();
        } catch (_) {
          if (getIt.isRegistered<OutboxService>()) getIt<OutboxService>().start();
          rethrow;
        }
      },
    );
  }

  @override
  Future<RepositoryResult<bool>> retireLegacySession() async {
    final predates = await _sessionRepository.predatesServerKey();
    // An error here is a keychain that cannot be read right now - a valid
    // session as likely as an old one - and never a reason to wipe.
    if (predates.data != true) return const RepositoryResult<bool>.success(data: false);
    logRepository.debug(target: this, message: 'bootstrap: a session paired before the secure channel, pairing again');
    final out = await logout(forced: true);
    return out.hasData ? const RepositoryResult<bool>.success(data: true) : out;
  }

  /// The single home of the "mutate the source of truth → re-derive app state"
  /// contract: run [mutate]; on success run [afterMutate] then re-derive via
  /// `fetchAppState`, on failure propagate the mutation error unchanged (no side
  /// effects, no re-derive, no false success).
  Future<RepositoryResult<bool>> _deriveAfter(
    Future<RepositoryResult<bool>> Function() mutate, {
    bool sessionExpired = false,
    Future<void> Function()? afterMutate,
  }) {
    return execute<bool>(() async {
      final mutated = await mutate();
      if (!mutated.hasData) return mutated;
      if (afterMutate != null) await afterMutate();
      await _appStateRepository.fetchAppState(sessionExpired: sessionExpired);
      return const RepositoryResult<bool>.success(data: true);
    });
  }
}
