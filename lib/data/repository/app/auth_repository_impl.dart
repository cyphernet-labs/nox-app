import 'package:injectable/injectable.dart';
import 'package:nox_app/data/sync/attachment_prefetch_service.dart';
import 'package:nox_app/data/sync/live_identity_handshake.dart';
import 'package:nox_app/general/pairing/device_keys.dart';
import 'package:nox_app/general/pairing/pairing_link.dart';
import 'package:nox_app/general/platform_utils.dart';
import 'package:nox_app/data/sync/live_session_starter.dart';
import 'package:nox_app/data/sync/outbox_service.dart';
import 'package:nox_app/di/configure_dependencies.dart';
import 'package:nox_app/data/exception/base_repository_helper.dart';
import 'package:nox_app/di/global_aliases.dart';
import 'package:nox_app/domain/exception/repository_exception.dart';
import 'package:nox_app/domain/model/app/app_state_type.dart';
import 'package:nox_app/domain/repository/app/app_state_repository.dart';
import 'package:nox_app/domain/repository/app/auth_repository.dart';
import 'package:nox_app/domain/repository/app/session_repository.dart';
import 'package:nox_app/domain/repository/base/repository_result.dart';
import 'package:nox_app/domain/repository/chat/chat_repository.dart';
import 'package:nox_app/domain/repository/chat/message_repository.dart';
import 'package:nox_app/domain/repository/device/device_repository.dart';
import 'package:nox_app/domain/repository/chat/outbox_repository.dart';
import 'package:nox_app/domain/repository/file/file_repository.dart';
import 'package:nox_app/domain/repository/sync/sync_repository.dart';

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

  /// Signs in by presenting a pairing link, and lets the SERVER decide whether
  /// onboarding is due.
  ///
  /// The order is the whole point. Parse the link, remember which server it
  /// names, mint this device's key, pair, take the outcome from the answer, and
  /// only then move the navigation. Remembering the server FIRST is what makes
  /// the connection go to the machine the person actually presented — a
  /// compile-time address would pair with one server and send messages to
  /// another.
  ///
  /// The three refusals stay apart because the person's next action differs: a
  /// link that will not parse means "scan it again", an expired token means
  /// "issue a new invite", a rejected one means "this is not usable". A failed
  /// attempt rolls the session back, because a stored identity with no settled
  /// outcome would strand the next launch in onboarding.
  @override
  Future<RepositoryResult<bool>> signIn({required String identifier}) {
    return execute<bool>(() async {
      final PairingLink link;
      try {
        link = PairingLink.parse(identifier);
      } on PairingLinkException {
        // A link that will not parse: the person scans or pastes it again.
        return const RepositoryResult<bool>.error(exception: RepositoryException.invalidRequest);
      }

      final saved = await _sessionRepository.saveServer(address: link.authority, serverKey: link.serverKey);
      if (!saved.hasData) return saved;

      final handshake = liveIdentityHandshake;
      if (handshake == null) {
        // No live channel in this build (mock flavors). There is no server to
        // ask, so onboarding is due.
        final stored = await _sessionRepository.saveIdentifier(identifier: link.token, onboardingComplete: false);
        if (!stored.hasData) return stored;
        return _finishSignIn(onboardingComplete: false);
      }

      final seed = await _sessionRepository.deviceSecret();
      if (!seed.hasData) return RepositoryResult<bool>.error(exception: seed.exception!);

      try {
        final greeting = await handshake.pair(
          link: link,
          deviceKey: await DeviceKeys.publicKey(seed.data!),
          platform: PlatformUtils.family,
        );
        if (!greeting.outcomeStated) {
          await _sessionRepository.discardSignIn();
          return const RepositoryResult<bool>.error(exception: RepositoryException.connection);
        }
        // The identifier slot now holds the token this install paired with: it
        // is what makes readSession() report a session at all, and it is not a
        // secret any more - the key is.
        final stored = await _sessionRepository.saveIdentifier(identifier: link.token, onboardingComplete: false);
        if (!stored.hasData) return stored;
        if (greeting.created!) _sessionRepository.noteOnboardingStartedHere();
        // Re-greet, SIGNED. The connection `pair` ran on was greeted before
        // this device existed to the server, so it still speaks as whoever
        // greeted then; a message sent on it would carry that identity and come
        // back looking like a stranger's on the sender's own screen. Storing
        // the session first is what makes this greeting state a person.
        try {
          await handshake.greet();
        } on Object {
          // The pairing itself landed. A greeting that did not is an ordinary
          // reconnect away, and the session is already valid.
        }
        return _finishSignIn(onboardingComplete: !greeting.created!);
      } on PairingRefused catch (e) {
        await _sessionRepository.discardSignIn();
        return RepositoryResult<bool>.error(exception: e.expired ? RepositoryException.notFound : RepositoryException.authentication);
      } on Object catch (e, st) {
        // The TYPE only. A FormatException from a base64 decode carries the
        // offending source in its message, which here would be the link or the
        // key seed - and a token in a log is still a usable pairing credential
        // (Principle I, FR-035).
        logRepository.error(target: this, error: e.runtimeType, stackTrace: st);
        await _sessionRepository.discardSignIn();
        return const RepositoryResult<bool>.error(exception: RepositoryException.connection);
      }
    });
  }

  /// Revokes this device's own key before the local wipe, when there is a
  /// channel to say it on. Never blocks the logout: a person who chose to sign
  /// out must sign out.
  Future<void> _revokeOwnKey() async {
    final devices = getIt.isRegistered<DeviceRepository>() ? getIt<DeviceRepository>() : null;
    if (devices == null) return;
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

  @override
  Future<RepositoryResult<bool>> logout({bool forced = false}) {
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
        if (!forced) await _revokeOwnKey();
        return _sessionRepository.clear();
      },
      sessionExpired: forced,
      afterMutate: () async {
        // Close the live channel BEFORE emptying anything: an event applied
        // mid-wipe would repopulate the stores this is in the middle of
        // clearing, leaving a logged-out device holding someone's messages.
        if (getIt.isRegistered<LiveSessionStarter>()) await getIt<LiveSessionStarter>().stop();
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
          // The prefetch remembers which files it already tried. That memory
          // belongs to the identity that was signed in: without clearing it,
          // the next person's pictures are never fetched for the life of the
          // process, because their message ids may repeat ours.
          if (getIt.isRegistered<AttachmentPrefetchService>()) getIt<AttachmentPrefetchService>().reset();
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
