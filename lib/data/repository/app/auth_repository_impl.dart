import 'package:injectable/injectable.dart';
import 'package:nox_app/data/sync/attachment_prefetch_service.dart';
import 'package:nox_app/data/sync/live_identity_handshake.dart';
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

  /// Signs in, and lets the SERVER decide whether onboarding is due.
  ///
  /// The order is the whole point. It used to be: guess the outcome from a
  /// hardcoded set of two identifiers, store it, navigate, then connect. No
  /// real identifier was in that set, so everyone was treated as new - and the
  /// name they were then forced to type travelled to the server as a rename
  /// and overwrote the name they were known by.
  ///
  /// Now: store the identifier, greet, take the outcome from the answer, write
  /// it, and only then move the navigation. Storing the identifier FIRST is
  /// what makes the greeting state a person rather than going out anonymously;
  /// it moves no screen on its own, because nothing re-derives app state until
  /// the last step.
  ///
  /// A handshake that does not answer rolls the session back. Leaving a stored
  /// identifier with no outcome behind would strand the next launch in
  /// onboarding - the very state this method exists to stop handing out.
  @override
  Future<RepositoryResult<bool>> signIn({required String identifier}) {
    return execute<bool>(() async {
      // Normalize once and persist the SAME value, so the stored identity
      // cannot diverge from what the derivation was computed over (e.g. a
      // pasted trailing newline). Normalization, not format validation.
      final id = identifier.trim();
      final saved = await _sessionRepository.saveIdentifier(identifier: id, onboardingComplete: false);
      if (!saved.hasData) return saved;

      final handshake = liveIdentityHandshake;
      if (handshake == null) {
        // No live channel in this build (mock flavors). Behave as before:
        // there is no server to ask, so onboarding is due.
        return _finishSignIn(onboardingComplete: false);
      }

      try {
        final greeting = await handshake.greet();
        if (!greeting.outcomeStated) {
          // The server did not say. Guessing costs the person either their
          // naming step or their name, so we say so instead.
          await _sessionRepository.discardSignIn();
          return const RepositoryResult<bool>.error(exception: RepositoryException.connection);
        }
        // The server made this person just now, and the naming screen is next.
        // Remember it for this process, so a reconnect while they are typing
        // cannot report their own brand-new row back at them as "already known".
        if (greeting.created!) _sessionRepository.noteOnboardingStartedHere();
        return _finishSignIn(onboardingComplete: !greeting.created!);
      } on Object catch (e, s) {
        logRepository.error(target: this, error: e, stackTrace: s);
        await _sessionRepository.discardSignIn();
        return const RepositoryResult<bool>.error(exception: RepositoryException.connection);
      }
    });
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
  Future<RepositoryResult<bool>> completeOnboarding({String? label}) {
    return _deriveAfter(
      () => _sessionRepository.setOnboardingComplete(label: label),
      // Reconnect so the chosen name actually reaches the server. Stage 1 has
      // no `identity.setLabel` (contract §8.1 puts it in stage 2), so the
      // greeting is the ONLY place a label is stated — and by now the socket
      // has already greeted, under the server-assigned `User<random>`. Without
      // this the user picks a name and everyone else keeps seeing the old one
      // until something happens to reconnect the device.
      afterMutate: () async {
        if (getIt.isRegistered<LiveSessionStarter>()) await getIt<LiveSessionStarter>().restart();
      },
    );
  }

  @override
  Future<RepositoryResult<bool>> logout({bool forced = false}) {
    // Gate the re-derive on a successful wipe: a failed clear() (e.g. a secure-storage
    // PlatformException) must NOT report success while the identifier survives —
    // otherwise the user silently stays authorized (Constitution I: logout fully wipes).
    // After the session is cleared, drop the cached chats + messages so a re-login as a
    // different identity starts clean (Constitution I: full local wipe on identity switch).
    return _deriveAfter(
      _sessionRepository.clear,
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
